
# Cache class made to handle all inner
# @author Gonzalo Rizzo

class Cache
  # TODO: Save only given bytes of val!!
  # TODO: Verify "key?"
  def initialize(size = (1024 * 1024 * 1024), maxKeySize = (1024 * 1024))
    @size = size
    @max_key_size = size < maxKeySize ? size : maxKeySize
    @data = {}
    @cas_val = {}
    @key_size = {}
    @cas_accumulator = 0
    @next_evict = nil

    @mutex = Mutex.new
  end

  def evict
    return unless @next_evict && @next_evict <= Time.now.to_i
    @next_evict = nil
    @mutex.synchronize do
      @data.each do |k, v|
        if v[:exptime] != 0 && v[:exptime] <= Time.now.to_i
          @data.delete(k)
          @key_size.delete(k)
        elsif v[:exptime] != 0 && (!@next_evict || v[:exptime] < @next_evict)
          @next_evict = v[:exptime]
        end
      end
    end
  end

  def get(key)
    evict
    @mutex.synchronize do
      if @data.key?(key)
        (@data[key] = @data.delete(key)).merge(cas: @cas_val[key], bytes: @key_size[key])
      end
    end
  end

  def set(key, val = nil, bytes = nil, exptime = nil, flags = nil)
    # puts "set ---> #{key} - #{val}"
    evict
    @mutex.synchronize do
      if val
        if bytes
          @key_size[key] = bytes
        else
          bytes = val.to_s.bytes.length
        end
        @key_size[key] = bytes
        raise NoMemoryError, "Val's size(#{bytes}) is bigger than maxKeySize(#{@max_key_size})" if bytes > @max_key_size
      end

      @cas_val[key] = @cas_accumulator += 1

      unless @data.key?(key)
        @data[key] = {
          flags: nil,
          exptime: 0
        }
      end

      @data[key][:flags] = flags if flags
      if exptime
        @data[key][:exptime] = exptime
        # TODO: Rethink, use Number#between
        @next_evict = exptime if exptime != 0 && (!@next_evict || exptime < @next_evict)
      end

      #  The key is being deleted so as when I set it again it's plased in the
      # first position, making the first position, the most resently used
      @data[key] = @data.delete(key)

      if val
        @data[key][:data] = val.to_s

        used_bytes = 0
        @key_size.each do |_k, v|
          used_bytes += v
        end

        while used_bytes > @size
          deleted_key = @data.shift[0]
          used_bytes -= @key_size.delete(deleted_key)
        end

      end
    end
  end

  def key?(key)
    evict
    @data.key?(key)
  end

  def []=(key, val)
    set(key, val)
  end

  def delete(key)
    set(key, nil, nil, 1, nil)
  end

  def touch(key, exptime)
    set(key, nil, nil, exptime, nil)
  end

  def dump(client) # TODO: Delete
    @mutex.synchronize do
      @data.each do |k, _v|
        client.sendmsg("#{k} -> #{@key_size[k]}\r\n")
      end
    end
  end

  alias [] get
  private :evict
end
