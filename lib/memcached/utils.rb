module Memcached
  module Utils
    def self.random_string(size = 8) # :nodoc: all
      return unless (size = Integer(size))
      output = []
      size.times do
        output << (rand(33..126)).chr
      end
      output.join
    end

    def self.parse_exptime(exptime=nil) # TODO: Put in a different file
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
