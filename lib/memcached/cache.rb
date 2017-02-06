module Memcached
  # Class +Cache+ provides an easy way to store volatile data on a limited
  # ammount of space. Also, it provides a mechanism to delete data after
  # a given unixstamp.
  #
  # You should not expect that every time you store a key, it will be stored the
  # next time you try to access it since it may had been deleted in order to
  # make space for new keys
  class Cache
    # Creates a new  Memcached::Cache object
    #
    # size:: Ammount of bytes that the cache should be able to hold
    #
    # maxKeySize:: Maximum size in bytes of a single key. It has to be
    #              less than the size of the cache.
    def initialize(size = (1024 * 1024), maxKeySize = size)
      @size = size

      #  If the max size of a single key is more than the size of the cache
      # the max size of a single key will be the size of the cache
      @max_key_size = size < maxKeySize ? size : maxKeySize

      @data = {}
      @cas_val = {}
      @key_size = {}
      @cas_accumulator = 0
      @next_evict = nil

      @mutex = Mutex.new
    end

    # Returns all the stored data related to the given +key+ in a Hash
    # The keys on the returned Hash are:
    #
    # :flags::   A general purpose Integer stored alongside the value.
    #
    # :exptime:: The unixstamp when the value is expected to be deleted.
    #
    # :val::     The stored value.
    #
    # :bytes::   The size in bytes of the value.
    #
    # :cas::     An Integer that changes when the value has changed used to
    #            verify if the value has changed since the last time it was
    #            fetched
    #
    # Example:
    #
    #   require 'memcached/cache'
    #
    #   cache = Memcached::Cache.new
    #   cache[:foo] = "bar"
    #   cache.get(:foo)
    #   # => {:flags=>nil, :exptime=>0, :val=>"bar", :bytes=>3, :cas=>1}
    def get(key)
      evict
      @mutex.synchronize do
        if @data.key?(key)
          #  The content of the key is deleted and re added from the data hash
          # in order to move it to the end of the hash while returning the value
          # of the key at the same time
          #
          #  The reason to move each key to the end of the hash each time one
          # key is requested is because this way least used keys are left in the
          # start of the hash, so when it is needed to delete a key, the first
          # key, which is the least used, is deleted first
          data = (@data[key] = @data.delete(key))

          # The returned hash is merged with the cas and the bytes of the value
          data.merge(bytes: @key_size[key], cas: @cas_val[key])
        end
      end
    end

    # Stores information about the +key+, this information is given by the Hash,
    # +data+, wich can contain the followin keys:
    #
    # exptime:: A unixstamp that represents when the value will expire
    #
    # val:: The value to store
    #
    # flags:: A general purpose Integer
    def set(key, data)
      raise ArgumentError, 'Data must be a hash' unless data.is_a? Hash

      val = data[:val]
      exptime = data[:exptime]
      flags = data[:flags]

      # First we have to clean up the cache
      evict

      @mutex.synchronize do
        # If the key is not in the cache already, initialize it
        unless @data.key?(key)
          @data[key] = {
            flags: 0,
            exptime: 0
          }
        end

        #  Deleting and storing a key agains moves the key to the last position
        # in the Hash, doing it every time a key is updated ends up with the
        # least used keys in the beggining of the hash.
        @data[key] = @data.delete(key)

        # Since the key is being updated the cas has to be updated
        @cas_val[key] = (@cas_accumulator += 1)

        # If a flag was given, update it
        @data[key][:flags] = flags if flags

        # If an exptime was given, update it and try to update next evict too
        if exptime
          @data[key][:exptime] = exptime
          update_next_evict(exptime)
        end

        if val
          @key_size[key] = val.to_s.bytes.length
          raise NoMemoryError,"The given value's size(#{@key_size[key]}) is bigger than the maximum allowed(#{@max_key_size})" if @key_size[key]  > @max_key_size

          @data[key][:val] = val.to_s

          verify_used_bytes

        end
      end
    end

    # Returns true if the +key+ is stored in the cache
    def key?(key)
      evict
      @data.key?(key)
    end

    # Returns the stored value of the +key+
    #
    # Sugarcode for:
    #  cache.get(key)[:val]
    def [](key)
      get(key)[:val] if key?(key)
    end

    # Stores a value inside the +key+
    #
    # Sugarcode for:
    #  cache.set(key, :val => value)
    def []=(key, value)
      set(key, :val => value)
    end

    # Deletes the given +key+ from the cache
    def delete(key)
      @data.delete(key)
      @key_size.delete(key)
    end

    # Changes the +exptime+ of a +key+
    def touch(key, exptime)
      set(key, :exptime => exptime)
    end

    # Lists the keys inside the cache
    def keys
      @data.keys
    end

    # Returns the size of the cache
    attr_reader :size

    # Returns the maximmum size allowed per key
    attr_reader :max_key_size

    # Changes the size of the cache
    def size=(size)
      @mutex.synchronize do

        if size < @size
          @size = size
          verify_used_bytes
        else
          @size = size
        end

        @max_key_size = @size if @size < @max_key_size

      end
    end

    # Changes the maximum ammount of bytes per key
    def max_key_size=(max_key_size)
      @max_key_size = @size < @max_key_size ? @size : max_key_size
    end

    private

    # Cleans the cache from expired keys but only when it's needed.
    #
    # An evict is needed after the current timestamp reaches the one stored in
    # @next_evict, and the timestamp stored in @next_evict is the closest
    # exptime. This way every time evict cleans the cache at least one
    # key is deleted
    def evict
      # Returns if an evict is not needed of if there is no upcoming evict
      return if Time.now.to_i < @next_evict rescue false

      @mutex.synchronize do
        @data.each do |k, v|
          unless v[:exptime] == 0

            # If the exptime of the current time is before now it has to be
            #  deleted
            if v[:exptime] <= Time.now.to_i
              delete(k)

              update_next_evict(v[:exptime])
            end

          end
        end
      end
    end

    # Tries to update the time for the next evict given an exptime.
    # If an evict isn't programmed or if the given exptime is before the next
    #  programmed evict, set the current key exptime as the next evict
    # An exptime of zero is not valid.
    def update_next_evict(exptime)
      return if exptime == 0
      @next_evict = exptime if (!@next_evict || exptime < @next_evict)
    end

    # Sums up the ammount of used bytes and if larget than @size it deletes keys
    #  until there is room for more keys
    def verify_used_bytes
      # Calculates the used bytes
      used_bytes = 0
      @key_size.each do |_k, v|
        used_bytes += v
      end

      #  If the ammount of used bytes is larger than the size of the cache,
      #  delete keys from the cache until the cache isn't full
      while used_bytes > @size
        #  Shifting a Hash returns an array where the first element is the
        # key of the shifted element
        deleted_key = @data.shift[0]
        used_bytes -= @key_size.delete(deleted_key)
      end
    end
  end
end
