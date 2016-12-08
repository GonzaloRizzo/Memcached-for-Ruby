require 'socket'
require_relative 'cache'
Thread::abort_on_exception = true
#todo: Error on max size reached
SERVER = TCPServer.open(11211) #TODO: Change port with an option
CACHE = Cache.new(1024*1024*20, 1024*1024) # 1gb CACHE with 1mb per value


def parseExptime(exptime=nil)
  if ! exptime || exptime == 0
    0 # Don't expire
  elsif exptime < 0
    1 # Already expired
  elsif exptime < 2592000 # 30 days in seconds
    Time.now.to_i + exptime # Expires in exptime seconds
  else
    exptime # Expires on exptime unixstamp
  end
end

def update_command(client, msg)
  if msg[0] == "cas"
    opcode, key, flags, exptime, bytes, cas, noreply = msg
    unless cas
      client.sendmsg("ERROR\r\n")
      return
    end
  else
    opcode, key, flags, exptime, bytes, noreply = msg
    unless bytes
      client.sendmsg("ERROR\r\n")
      return
    end
  end

  begin

    if noreply == "noreply"
      noreply = true
    else
      noreply = false
    end

    flags=Integer(flags)
    exptime=parseExptime(Integer(exptime))
    bytes=Integer(bytes)
    cas_unique= opcode == "cas" ? Integer(cas_unique) : nil

  rescue TypeError, ArgumentError
    client.sendmsg("CLIENT_ERROR bad command line format\r\n") unless noreply
    return
  end


  if data = client.read(bytes+2)

    unless data[bytes..bytes+2] == "\r\n"
      client.sendmsg("CLIENT_ERROR bad data chunk\r\n") unless noreply
      return
    end

    data.chomp!

    case opcode.to_sym
    when :set
      CACHE.set(key, data, bytes, exptime, flags)
      client.sendmsg("STORED\r\n") unless noreply
    when :add
      unless CACHE.key?(key)
        CACHE.set(key, data, bytes, exptime, flags)
        client.sendmsg("STORED\r\n") unless noreply
      else
        client.sendmsg("NOT_STORED\r\n") unless noreply
      end
    when :replace
      if CACHE.key?(key)
        CACHE.set(key, data, bytes, exptime, flags)
        client.sendmsg("STORED\r\n") unless noreply
      else
        client.sendmsg("NOT_STORED\r\n") unless noreply
      end
    when :append
      if CACHE.key?(key)
        CACHE.set(key, CACHE[key][:data] + data, bytes)
        client.sendmsg("STORED\r\n") unless noreply
      else
        client.sendmsg("NOT_STORED\r\n") unless noreply
      end
    when :prepend
      if CACHE.key?(key)
        CACHE.set(key, data + CACHE[key][:data], bytes)
        client.sendmsg("STORED\r\n") unless noreply
      else
        client.sendmsg("NOT_STORED\r\n") unless noreply
      end
    when :cas
      if CACHE.key?(key) && CACHE[key][:cas] == cas
        CACHE.set(key, data, bytes)
        client.sendmsg("STORED\r\n") unless noreply
      else
        client.sendmsg("NOT_FOUND\r\n") unless noreply
      end
    end
  end
end


def retrieval_command(client, msg)
  opcode,*keys=msg
  keys.each do |key|
    if v = CACHE[key]
      client.sendmsg("VALUE #{key} #{v[:flags]} #{v[:bytes]}")
      if (opcode == "gets")
        client.sendmsg(" #{v[:cas]}")
      end
      client.sendmsg("\r\n")
      client.sendmsg( v[:data] + "\r\n" )
    else
      "key not found"
    end
  end
  client.sendmsg( "END\r\n" )
end

def incr_decr_command(client, msg)
  opcode,key,step, noreply=msg

  if noreply == "noreply"
    noreply = true
  else
    noreply = false
  end

  unless step
    client.sendmsg("ERROR\r\n") unless noreply
    return
  end


  if CACHE.key?(key)
    if step=Integer(step) rescue nil

      step *= -1 if opcode == "decr"

      currentval = CACHE[key][:data]

      if currentval = Integer(currentval) rescue nil
        CACHE[key] = currentval + step
      else
        client.sendmsg("CLIENT_ERROR cannot increment or decrement non-numeric value\r\n") unless noreply
      end

    else
      client.sendmsg("CLIENT_ERROR invalid numeric delta argument\r\n") unless noreply
    end
  else
    client.sendmsg("NOT_FOUND\r\n") unless noreply
  end

end

def delete_command (client, msg)
  opcode, key, noreply = msg

  if noreply == "noreply"
    noreply = true
  else
    noreply = false
  end

  unless key
    client.sendmsg("ERROR\r\n") unless noreply
    return
  end



  if CACHE.key?(key)
    CACHE.delete(key)
    client.sendmsg("DELETED\r\n") unless noreply
  else
    client.sendmsg("NOT_FOUND\r\n") unless noreply
  end
end

def touch_command (client, msg)
  opcode, key, exptime, noreply = msg

  if noreply == "noreply"
    noreply = true
  else
    noreply = false
  end

  unless exptime
    client.sendmsg("ERROR\r\n") unless noreply
    return
  end



  if CACHE.key?(key)
    CACHE.touch(key, parseExptime(exptime))
    client.sendmsg("TOUCHED\r\n") unless noreply
  else
    client.sendmsg("NOT_FOUND\r\n") unless noreply
  end
end

loop do
  Thread.start(SERVER.accept) do |client|
    puts "New client from #{client.peeraddr[3]}"
    while  msg = client.gets
      puts "-> #{msg}"
      msg = msg.split
      case msg[0].to_s.to_sym
      when :set, :add, :replace, :append, :prepend, :cas
        update_command(client, msg)
      when :get, :gets
        retrieval_command(client, msg)
      when :incr, :decr
        incr_decr_command(client, msg)
      when :delete
        delete_command(client, msg)
      when :touch
        touch_command(client, msg)
      when :dump
        CACHE.dump(client)
      when :total_size
        client.puts(CACHE.totalSize)
      when :used_size
        client.puts(CACHE.usedSize)
      else
        client.sendmsg("ERROR\r\n")
      end
    end
    client.close
  end
end
