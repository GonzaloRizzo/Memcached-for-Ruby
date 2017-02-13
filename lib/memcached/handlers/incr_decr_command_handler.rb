require 'memcached/handlers/base_handler'
module Memcached
  module Handlers

    # Handles the incr and decr commands
    class IncrDecrCommandHandler < BaseHandler

      @handles = [:incr, :decr]

      # (see Memcached::Handlers::BaseHandler.handle)
      def handle(command, data)

        cache = data[:cache]
        client = data[:client]

        key, step, noreply = data[:argv]

        noreply = (noreply == "noreply" ? true : false)

        # If step is not defined it's because not every necesary argument was
        #  specified
        unless step
          client.sendmsg("ERROR\r\n") unless noreply
          return
        end

        # Checks if the key is present on the cache
        unless cache.key?(key)
          client.sendmsg("NOT_FOUND\r\n") unless noreply
          return
        end

        # Checks if the given step is a valid integer
        unless (step = Integer(step) rescue nil)
          client.sendmsg("CLIENT_ERROR invalid numeric delta argument\r\n") unless noreply
          return
        end

        # Gets the current value from the cache
        currentval = cache[key]

        # Verifies that the stored value is a valid integer
        unless (currentval = Integer(currentval) rescue nil)
          client.sendmsg("CLIENT_ERROR cannot increment or decrement non-numeric value\r\n") unless noreply
          return
        end

        # If a decrement was requested instead of increment the step is
        #  converted into his negative
        step *= -1 if command == "decr"

        # Stores the incremented/decremented value
        cache[key] = currentval + step

        client.sendmsg(cache[key] + "\r\n")
      end


    end
  end
end
