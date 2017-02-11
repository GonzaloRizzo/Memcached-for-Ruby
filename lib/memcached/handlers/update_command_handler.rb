require 'memcached/handlers/base_handler'
require 'memcached/utils'
module Memcached
  module Handlers

    class UpdateCommandHandler < BaseHandler

      @handles = [:set, :add, :replace, :append, :prepend, :cas]

      def handle(command, data)

        argv = data[:argv]
        cache = data[:cache]
        client = data[:client]

        # Interprets argv
        if command == "cas"
          key, flags, exptime, bytes, cas, noreply = argv
          # If cas is not defined it's because not every necesary argument was specified
          unless cas
            client.sendmsg("ERROR\r\n")
            return
          end
        else
          key, flags, exptime, bytes, noreply = argv
          # If bytes is not defined it's because not every necesary argument was specified
          unless bytes
            client.sendmsg("ERROR\r\n")
            return
          end
        end

        noreply = (noreply == "noreply" ? true : false)


        # Casts input variables
        begin
          flags = Integer(flags)
          exptime = Memcached::Utils.parse_exptime(Integer(exptime))
          bytes = Integer(bytes)
          cas = (command == "cas" ? Integer(cas) : nil)
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
        case command.to_sym
        when :set
          cache.set(key, :val => data, :bytes => bytes, :exptime => exptime, :flags => flags)
          client.sendmsg("STORED\r\n") unless noreply
        when :add
          unless cache.key?(key)
            cache.set(key, :val => data, :bytes => bytes, :exptime => exptime, :flags => flags)
            client.sendmsg("STORED\r\n") unless noreply
          else
            client.sendmsg("NOT_STORED\r\n") unless noreply
          end
        when :replace
          if cache.key?(key)
            cache.set(key, :val => data, :bytes => bytes, :exptime => exptime, :flags => flags)
            client.sendmsg("STORED\r\n") unless noreply
          else
            client.sendmsg("NOT_STORED\r\n") unless noreply
          end
        when :append
          if cache.key?(key)
            stored_data = cache.get(key)
            cache.set(key, :val => stored_data[:val] + data, :bytes => stored_data[:bytes] + bytes)
            client.sendmsg("STORED\r\n") unless noreply
          else
            client.sendmsg("NOT_STORED\r\n") unless noreply
          end
        when :prepend
          if cache.key?(key)
            stored_data = cache.get(key)
            cache.set(key, :val => data + stored_data[:val], :bytes => stored_data[:bytes] + bytes)
            client.sendmsg("STORED\r\n") unless noreply
          else
            client.sendmsg("NOT_STORED\r\n") unless noreply
          end
        when :cas
          if cache.key?(key)
            if cache.get(key)[:cas] == cas
              cache.set(key, :val => data, :bytes => bytes)
              client.sendmsg("STORED\r\n") unless noreply
            else
              client.sendmsg("EXISTS\r\n") unless noreply
            end
          else
            client.sendmsg("NOT_FOUND\r\n") unless noreply
          end
        end

      end
    end
  end
end
