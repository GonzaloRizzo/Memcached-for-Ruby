module Memcached
  module Handlers

    class TouchCommandHandler < BaseHandler

      @handles = [:touch]

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
        cache.touch(key, parse_exptime(Integer(exptime)))
        client.sendmsg("TOUCHED\r\n") unless noreply
      end


      private

      # Parses a memcached's exptime into a unixstamp.
      def parse_exptime(exptime=nil) # TODO: Put in a different file
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
    end
  end
end
