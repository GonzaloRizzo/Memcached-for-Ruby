require 'memcached/handlers/base_handler'
require 'memcached/utils'
module Memcached
  module Handlers

    # Handles the touch command
    class TouchCommandHandler < BaseHandler

      @handles = [:touch]

      # (see Memcached::Handlers::BaseHandler.handle)
      def handle(_command, data)

        cache = data[:cache]
        client = data[:client]

        key, exptime, noreply  = data[:argv]

        noreply = (noreply == 'noreply' ? true : false)


        # If exptime is not defined it's because not every necesary argument was specified
        unless exptime
          client.sendmsg("ERROR\r\n") unless noreply
          return
        end

        # Verifies that the key is in the cache
        unless cache.key?(key)
          client.sendmsg("NOT_FOUND\r\n") unless noreply
          return
        end

        # Changes the exptime from the given key on the cache
        cache.touch(key, Memcached::Utils.parse_exptime(Integer(exptime)))
        client.sendmsg("TOUCHED\r\n") unless noreply
      end
    end
  end
end
