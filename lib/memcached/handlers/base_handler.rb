require 'singleton'
module Memcached
  # Module which stores the handlers that will be loaded by the
  # {Memcached::Server}
  module Handlers
    # Base handler object to be implemented by all the handlers of
    # {Memcached::Server}
    class BaseHandler
      include Singleton

      @handles = []

      # (see Memcached::Handlers::BaseHandler.handle)
      def handle(_msg, _data)
        nil
      end

      # Method to execute by {Memcached::Router#route} when {handles} matches
      # a routed message
      def self.handle(msg, data=nil)
        self.instance.handle(msg, data)
      end

      # Method that returns an array with the commands that handle is able to
      # handle
      # @return Array<Symbol>
      def self.handles
        @handles or []
      end

    end

  end
end
