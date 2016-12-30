require_relative 'cache'

def parseExptime(exptime = nil)
  if !exptime || exptime == 0
    0 # Don't expire
  elsif exptime < 0
    1 # Already expired
  elsif exptime < 2_592_000 # 30 days in seconds
    Time.now.to_i + exptime # Expires in exptime seconds
  else
    exptime # Expires on exptime unixstamp
  end
end

cache = Cache.new
cache.set(1, 'ga', nil, parseExptime(7))
cache.set(2, 'ro', nil, parseExptime(10))
cache.set(3, 'Hr', nil)
cache.set(4, 'ao', nil, parseExptime(5))
cache.set(5, '00', nil, parseExptime(20))

cache[5] = 'jaja'
loop do
  p '-----'
  p cache[1]
  p cache[2]
  p cache[3]
  p cache[4]
  p cache[5]
  sleep 1
end
