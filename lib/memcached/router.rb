
module Memcached
  class Router

    def initialize
      @handlers = {}
    end

    def register(*commands, &handler)
      raise LocalJumpError, "No block given" unless handler

      # Asociates the callback with each given command
      commands.each do |command|
        # Creates the array for the given command if not created already
        @handlers[String(command).to_sym] ||= []

        @handlers[String(command).to_sym].push handler
      end
    end

    def route(msg, data=nil)

      # Initialized "data" if it is not valid
      data = {} unless data.is_a? Hash

      # Flag to return if the message was routed
      routed = false

      msg = msg.split

      command = msg[0]
      data[:argv] = msg[1..-1] unless data[:argv]


      handlers = @handlers[String(command).to_sym]

      if handlers
        handlers.each do |handler|
          routed = true
          handler.call(command, data)
        end
      end

      # Returns whether the message was routed or not
      routed
    end

    def routeable?(msg)
      return @handlers.include?(msg.split[0].to_sym)
    end
  end
end
