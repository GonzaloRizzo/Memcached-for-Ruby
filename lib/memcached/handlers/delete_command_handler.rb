module Memcached
  module Handlers

    class DeleteCommandHandler < BaseHandler

      @handles = [:delete]

      def handle(_command, data)

        cache = data[:cache]
        client = data[:client]

        key, noreply = data[:argv]

        noreply = (noreply == 'noreply' ? true : false)

        # If key is not defined it's because not every necesary argument was specified
        unless key
          client.sendmsg("ERROR\r\n") unless noreply
          return
        end

        # Verifies that the key is in the cache
        unless cache.key?(key)
          client.sendmsg("NOT_FOUND\r\n") unless noreply
          return
        end

        # Deletes the key from the cache
        cache.delete(key)
        client.sendmsg("DELETED\r\n") unless noreply

      end

    end
  end
end