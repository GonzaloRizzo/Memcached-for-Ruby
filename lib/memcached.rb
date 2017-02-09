require 'socket'
require 'logger'
require 'memcached/cache'
require 'memcached/router'

require 'memcached/handlers/base_handler.rb'

# Loads command handlers from the handlers folder
# Command handlers file names MUST end with Handler.rb
Dir[File.dirname(__FILE__) + '/memcached/handlers/*_handler.rb'].each {|file| require file }

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

      # Creates a new router for the server
      @router = Memcached::Router.new

      # Registers handlers from Memcached::handlers
       Memcached::Handlers.constants.each do |handler|
         handler =  Memcached::Handlers.const_get handler
         next unless handler < Memcached::Handlers::BaseHandler
         next if handler.handles.empty?

         @router.register(*handler.handles, &handler.method(:handle))
       end

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
            new_thread = create_client_thread(new_client)

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
      # Here I had to put a small margin of 100ms here because of connections
      #  that were made very close to the stop of the server.
      # When a new connection is made and then this method is inmediately
      #  called, as you can see in the spec 'closes open connections' of '#stop',
      #  from times to times the connection falls in some kind of limbo where
      #  this server didn't accept the connection but the client thinks that it
      #  did. So with this method I wait 100ms for new connections so they can
      #  be properly closed, the problem is that, in theory, when a connection is
      #  made 100ms after this method is called they fall in the same problem
      #  that I described before. So this workaround only fixes the spec that
      #  I mentioned before
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
    def create_client_thread(socket)
      Thread.new(socket) do |client|
        # Tries to store the client's IP and closes the connection if it fails.
        # Was the connection already closed?
        addr = client.peeraddr[3] rescue nil

        client.close unless addr
        LOG.info "New connection from #{addr}"
        #  rescue nil
        while (msg = client.gets("\r\n")  rescue nil)
          LOG.debug "#{addr} --> #{msg.inspect}"

          next if @router.route(msg, {
            client:client,
            cache:@cache
            })

          client.sendmsg("ERROR\r\n")

        end
        client.close
      end
    end



  end
end
