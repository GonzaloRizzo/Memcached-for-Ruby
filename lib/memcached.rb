require 'socket'
require 'logger'
require 'memcached/cache'


# :stopdoc:
Thread::abort_on_exception = true
# :startdoc:


module Memcached
  LOG = Logger.new STDOUT # :nodoc:
  LOG.level = Logger::INFO
  LOG.progname = "Memcached"

  # Class +Server+ provides a server which implements the memcached's protocol
  class Server
    # Creates a new Memcached::Server object on a given port
    #
    # port::  Port where the server should listen for connections. If 0 is given
    #         a random port will be provided (default: 11211)
    #
    # cache:: An instance of Memcached::Cache to attach into the server.
    #         defaults to a 512MiB cache
    def initialize(port=11211, cache=nil)
      @port = port
      @listening_thread = nil
      @client_threads = []
      @tcp_server = nil

      # If cache is not defined create a new one
      @cache = (cache or Cache.new(1024*1024*512))
    end

    attr_reader :port
    attr_reader :cache

    # Starts the server so it can listen for commands on the given port
    def start
      return @listening_thread if @listening_thread

      # Creates the tcp server on the given port.
      # If the given port is 0 a random port will be asigned
      @tcp_server = TCPServer.open(@port)

      # The correct port is stored on @port in case a random port was requested
      @port = @tcp_server.addr[1] if @port == 0

      LOG.info "Listening on #{@port}"

      @listening_thread = Thread.new do
        loop do

          # Waits for a new client
          new_client = @tcp_server.accept rescue nil

          if new_client.is_a? TCPSocket
            # Registers the new client's thread
            new_thread = createClientThread(new_client)

            # Registers the client on the Thread
            new_thread[:client] = new_client

            # Adds the thread to the list of client's threads
            @client_threads << new_thread
          end

          #Checks if the end of the loop was requested
          if Thread.current[:exit?]
            @tcp_server.close
            break
          end
        end

        LOG.debug "Listening thread stopped"
      end

    end

    # Stops the server and releases the port
    def stop
      return unless @listening_thread

      # Requests the listening thread to stop
      @listening_thread[:exit?] = true

      # WARNING: Workaround!!
      #   Here I had to put a small margin of 100ms because of connections that
      # were made very close to the stop of the server.
      #   When a new connection is made and then this method is inmediately
      # called, as you can see in the spec 'closes open connections' of '#stop',
      # from times to times the connection falls in some kind of limbo where
      # this server didn't accept the connection but the client thinks that it
      # did. So with this method I wait 100ms for new connections so they can
      # be properly closed, the problem is that, in theory, when a connection is
      # made 100ms after this method is called they fall in the same problem
      # that I described b efore. So this workaround only fixes the spec that
      # I mentioned before
      # TODO: Check this
      unless (IO.select([@tcp_server], nil, nil, 0.1) rescue nil)
        @tcp_server.close
      end

      # Waits for the listening thread to end
      @listening_thread.join

      #  Removes client threads from the list while closing their connections
      #  and waiting for the threads to finish
      until @client_threads.empty?
        thr = @client_threads.pop
        thr[:client].close
        thr.join
      end

    end

    # Returns true if the server is online
    def online?
      if @tcp_server.is_a? TCPServer
        # If it's not closed, it's online.
        ! @tcp_server.closed?
      else
        false
      end
    end

    # Changes the port of the server. The server has to be closed first.
    def port=(port)
      raise "Cannot change the port when the server is open" if online?
      @port=port
    end

    private

    # Creates a new thread for a client that will process all commands recived
    #  by this client
    def createClientThread(socket)
      Thread.new(socket) do |client|
        # Tries to store the client's IP and closes the connection if it fails.
        # Was the connection already closed?
        addr = client.peeraddr[3] rescue nil
        client.close unless addr
        LOG.info "New connection from #{addr}"
        #  rescue nil
        while (msg = client.gets("\r\n")  rescue nil)
          LOG.debug "#{addr} --> #{msg.inspect}"

          # Routes user input
          argv = msg.split
          case argv[0].to_s.to_sym
          when :set, :add, :replace, :append, :prepend, :cas
            update_command(client, argv)
          when :get, :gets
            retrieval_command(client, argv)
          when :incr, :decr
            incr_decr_command(client, argv)
          when :delete
            delete_command(client, argv)
          when :touch
            touch_command(client, argv)
          else
            LOG.debug "#{addr} <-> unknown command!!"
            client.sendmsg("ERROR\r\n")
          end

        end
        p "CLOSING"
        client.close
      end
    end

    # Parses a memcached's exptime into a unixstamp.
    def parseExptime(exptime=nil)
      if ! exptime || exptime == 0
        0 # Don't expire
      elsif exptime < 0
        1 # Already expired
      elsif exptime < 2592000 # 30 days in seconds
        Time.now.to_i + exptime # Expires in "exptime" seconds
      else
        exptime # Expires on the given unixstamp
      end
    end

    # Process an update related command:
    #  set, add, replace, prepend, append, cas
    def update_command(client, argv)

      # Interprets argv
      if argv[0] == "cas"
        opcode, key, flags, exptime, bytes, cas, noreply = argv
        # If cas is not defined it's because not every necesary argument was specified
        unless cas
          client.sendmsg("ERROR\r\n")
          return
        end
      else
        opcode, key, flags, exptime, bytes, noreply = argv
        # If bytes is not defined it's because not every necesary argument was specified
        unless bytes
          client.sendmsg("ERROR\r\n")
          return
        end
      end

      noreply = noreply == "noreply" ? true : false

      # Casts input variables
      begin
        flags = Integer(flags)
        exptime = parseExptime(Integer(exptime))
        bytes = Integer(bytes)
        cas = opcode == "cas" ? Integer(cas) : nil
      rescue TypeError, ArgumentError
        client.sendmsg("CLIENT_ERROR bad command line format\r\n") unless noreply
        return
      end


      # Reads input data
      data = client.read bytes + 2

      # If input data doasn't end with \r\n the data sent is wrong
      unless data[-2,2] == "\r\n"
        client.sendmsg("CLIENT_ERROR bad data chunk\r\n") unless noreply
        return
      end

      # We dont wan't to waste space on redundant newlines, right?
      data.chomp!

      # Decides final action
      case opcode.to_sym
      when :set
        @cache.set(key, :val => data, :bytes => bytes, :exptime => exptime, :flags => flags)
        client.sendmsg("STORED\r\n") unless noreply
      when :add
        unless @cache.key?(key)
          @cache.set(key, :val => data, :bytes => bytes, :exptime => exptime, :flags => flags)
          client.sendmsg("STORED\r\n") unless noreply
        else
          client.sendmsg("NOT_STORED\r\n") unless noreply
        end
      when :replace
        if @cache.key?(key)
          @cache.set(key, :val => data, :bytes => bytes, :exptime => exptime, :flags => flags)
          client.sendmsg("STORED\r\n") unless noreply
        else
          client.sendmsg("NOT_STORED\r\n") unless noreply
        end
      when :append
        if @cache.key?(key)
          stored_data = @cache.get(key)
          @cache.set(key, :val => stored_data[:val] + data, :bytes => stored_data[:bytes] + bytes)
          client.sendmsg("STORED\r\n") unless noreply
        else
          client.sendmsg("NOT_STORED\r\n") unless noreply
        end
      when :prepend
        if @cache.key?(key)
          stored_data = @cache.get(key)
          @cache.set(key, :val => data + stored_data[:val], :bytes => stored_data[:bytes] + bytes)
          client.sendmsg("STORED\r\n") unless noreply
        else
          client.sendmsg("NOT_STORED\r\n") unless noreply
        end
      when :cas
        if @cache.key?(key)
          if @cache.get(key)[:cas] == cas
            @cache.set(key, :val => data, :bytes => bytes)
            client.sendmsg("STORED\r\n") unless noreply
          else
            client.sendmsg("EXISTS\r\n") unless noreply
          end
        else
          client.sendmsg("NOT_FOUND\r\n") unless noreply
        end
      end

    end

    # Process retrieval related commands:
    #  get, gets
    def retrieval_command(client, msg)

      # Interprets argv
      opcode,*keys=msg

      # Verifies that at least one key was given
      if keys.empty?
        client.sendmsg("ERROR\r\n")
        return
      end

      keys.each do |key|
        if (v = @cache.get(key))

          # Sends header without finishing the line
          client.sendmsg("VALUE #{key} #{v[:flags]} #{v[:bytes]}")

          if (opcode == "gets")
            # If opcode is gets appends cas to the headder
            client.sendmsg(" #{v[:cas]}")
          end

          # Finishes the line
          client.sendmsg("\r\n")

          # Sends the data inside the key
          client.sendmsg( v[:val] + "\r\n" )

        end
      end

      # Sends the tail of the packet indicating the end of the message
      client.sendmsg("END\r\n")

    end

    # Process increment and decrement comamands:
    #  incr, decr
    def incr_decr_command(client, msg)
      opcode, key, step, noreply = msg

      noreply = noreply == "noreply" ? true : false

      # If step is not defined it's because not every necesary argument was specified
      unless step
        client.sendmsg("ERROR\r\n") unless noreply
        return
      end

      # Checks if the key is present on the cache
      unless @cache.key?(key)
        client.sendmsg("NOT_FOUND\r\n") unless noreply
        return
      end

      # Checks if the given step is a valid integer
      unless (step = Integer(step) rescue nil)
        client.sendmsg("CLIENT_ERROR invalid numeric delta argument\r\n") unless noreply
        return
      end

      # Gets the current value from the cache
      currentval = @cache[key]

      # Verifies that the stored value is a valid integer
      unless (currentval = Integer(currentval) rescue nil)
        client.sendmsg("CLIENT_ERROR cannot increment or decrement non-numeric value\r\n") unless noreply
        return
      end

      #  If a decrement was requested instead of increment the step is converted
      # into his negative
      step *= -1 if opcode == "decr"

      # Stores the incremented/decremented value

      @cache[key] = currentval + step

      client.sendmsg(@cache[key] + "\r\n")
    end

    # Process the delete commmand:
    #  delete
    def delete_command(client, msg)
      _opcode, key, noreply = msg

      noreply = noreply == 'noreply' ? true : false

      # If key is not defined it's because not every necesary argument was specified
      unless key
        client.sendmsg("ERROR\r\n") unless noreply
        return
      end

      # Verifies that the key is in the cache
      unless @cache.key?(key)
        client.sendmsg("NOT_FOUND\r\n") unless noreply
        return
      end

      # Deletes the key from the cache
      @cache.delete(key)
      client.sendmsg("DELETED\r\n") unless noreply

    end

    # Process the touch commmand:
    #  touch
    def touch_command(client, msg)
      _opcode, key, exptime, noreply = msg

      noreply = noreply == 'noreply' ? true : false

      # If exptime is not defined it's because not every necesary argument was specified
      unless exptime
        client.sendmsg("ERROR\r\n") unless noreply
        return
      end

      # Verifies that the key is in the cache
      unless @cache.key?(key)
        client.sendmsg("NOT_FOUND\r\n") unless noreply
        return
      end

      # Changes the exptime from the given key on the cache
      @cache.touch(key, parseExptime(Integer(exptime)))
      client.sendmsg("TOUCHED\r\n") unless noreply

    end

  end
end
