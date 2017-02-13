module Memcached
  # Useful methods used in different parts of the Memcached module
  module Utils

    # Generates a random string with the given length
    #
    # @param size [Numeric] the length of the string
    # @return [String] the random string
    def self.random_string(size = 8)
      return unless (size = Integer(size))
      output = []
      size.times do
        output << (rand(33..126)).chr
      end
      output.join
    end

    # Parses a given Numeric value in seconds into an expiration timestamp
    # following the these rules depending on the provided value:
    #
    # - If no value is provided it defaults to 0, which means that it never
    #   expires
    #
    # - If it is negative, it returns 1, which means an already expired value
    #
    # - If it is less than 2592000, which is, the equivalent of 30 days in
    #   seconds, it will return a timestamp representing now plus the given
    #   value in seconds
    #
    # - If any of this conditions is met, the returned value will be the same
    #   as the provided value
    #
    # @param exptime [Numeric] a numeric value in seconds
    # @return [Numeric] parsed timestamp
    def self.parse_exptime(exptime=0) # TODO: Put in a different file
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
