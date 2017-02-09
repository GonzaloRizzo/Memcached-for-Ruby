
module Memcached
  module Handlers

    class RetrievalCommandHandler < BaseHandler

      @handles = [:get, :gets]

      def handle(command, data)

        keys = data[:argv]
        cache = data[:cache]
        client = data[:client]

        # Verifies that at least one key was given
        if keys.empty?
          client.sendmsg("ERROR\r\n")
          return
        end

        keys.each do |key|
          if (v = cache.get(key))

            # Sends header without finishing the line
            client.sendmsg("VALUE #{key} #{v[:flags]} #{v[:bytes]}")

            if (command == "gets")
              # If command is gets appends cas to the headder
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

    end
  end
end
