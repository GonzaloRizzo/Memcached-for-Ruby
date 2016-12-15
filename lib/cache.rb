class Cache
  #TODO: Save only given bytes of val!!
  #TODO: Verify "key?"
  def initialize(size=(1024*1024*1024), maxKeySize=(1024*1024))
    @size=size
    @maxKeySize = size < maxKeySize ? size : maxKeySize
    @data={}
    @casval={}
    @keysize={}
    @casaccumulator=0

    @next_evict = nil

    @mutex = Mutex.new
  end

  def evict
    if @next_evict && @next_evict <= Time.now.to_i
      @next_evict = nil
      @mutex.synchronize do
        @data.each do |k, v|
          if v[:exptime] != 0 && v[:exptime] <= Time.now.to_i
            p "deleted #{k} !!!!! EVICT <<<<<<<<<<<<<<<<<<<<<<<"
            @data.delete(k)
            @keysize.delete(k)
          else
            @next_evict = v[:exptime] if v[:exptime] != 0 && ( ! @next_evict || v[:exptime] < @next_evict)
          end
        end

      end
    end
  end

  def get(key)
    evict
    @mutex.synchronize do

      if @data.key?(key)
        (@data[key] = @data.delete(key)).merge({cas: @casval[key], bytes: @keysize[key]})
      end

    end
  end

  def set(key, val=nil, bytes=nil, exptime=nil, flags=nil)
  #  puts "set ---> #{key} - #{val}"
    evict
    @mutex.synchronize do
      if val
        if bytes
          @keysize[key]=bytes
        else
          bytes=val.to_s.bytes.length
        end
        @keysize[key]=bytes
        raise NoMemoryError, "Val's size(#{bytes}) is bigger than maxKeySize(#{@maxKeySize})" if bytes > @maxKeySize
      end

      @casval[key] = @casaccumulator+=1

      unless @data.key?(key)
        @data[key]={
          flags: nil,
          exptime:0
        }
      end

      @data[key][:flags] = flags if flags
      if exptime
        @data[key][:exptime] = exptime
        @next_evict = exptime if exptime != 0 && ( ! @next_evict || exptime < @next_evict)
      end

      #  The key is being deleted so as when I set it again it's plased in the
      # first position, making the first position, the most resently used
      @data[key] = @data.delete(key)

      if (val)

        @data[key][:data] = val.to_s

        usedBytes=0
        @keysize.each do |k,v|
          usedBytes+=v
        end


        while usedBytes > @size
          p "#{usedBytes} > #{@size}  <<<<<<<<<<<<<<<<<----------------"
          deletedKey = @data.shift[0]
          usedBytes -= @keysize.delete(deletedKey)
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

  def dump(client)
    @mutex.synchronize do
      @data.each do |k,v|
        client.sendmsg("#{k} -> #{@keysize[k]}\r\n")
      end
    end
  end

  alias_method :[], :get
  private :evict

end
