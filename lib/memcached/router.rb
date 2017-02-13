module Memcached
  # {Memcached::Router} class is meant to, as the name suggests, route client's
  # input data to the corresponding handler.
  #
  # Handlers are registered by using the {#register} method.
  class Router

    def initialize
      @handlers = {}
    end

    # Registers a method to be routed by the {#route} method.
    #
    # @param *commands [String] a comma separated list of commands to handle
    #
    # @yieldparam command [String] command to handle
    # @yieldparam data [Hash] hash containing the +argv+ key with the parameters
    #             provided by {#route} and other keys provided by the same
    #             method
    # @raise [LocalJumpError] if a block was not povided
    #
    def register(*commands, &handler)
      raise LocalJumpError, "No block given" unless handler

      # Asociates the callback with each given command
      commands.each do |command|
        # Creates the array for the given command if not created already
        @handlers[String(command).to_sym] ||= []

        @handlers[String(command).to_sym].push handler
      end
    end

    # Routes a message to a registered handler
    #
    # @param message [String] message to route. The first word will be sent to
    #        the handler as the command and the rest of the words will be
    #        splited in an array and sent in the second parameter of the handler
    #        as the +argv+ key in a +Hash+
    # @param data [Hash] hash to append to the second parameter of the handler
    # @return [Boolean] whether the message was routed or not
    #
    # @see Memcached::Router#register
    #
    def route(message, data=nil)

      # Initialized "data" if it is not valid
      data = {} unless data.is_a? Hash

      # Flag to return if the message was routed
      routed = false

      message = message.split

      command = message[0]
      data[:argv] = message[1..-1] unless data[:argv]


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

    # @param message [String] Message to check if it is routeable or not
    # @return [Boolean] whether the message is routeble or not
    def routeable?(message)
      return @handlers.include?(message.split[0].to_sym)
    end
  end
end
