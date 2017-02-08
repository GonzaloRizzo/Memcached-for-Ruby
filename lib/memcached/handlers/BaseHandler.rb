require 'singleton'
module Memcached
  module Handlers

    class BaseHandler
      include Singleton

      @handles = []

      def handle(_msg, _argv)
        nil
      end

      def self.handle(msg, argv=nil) #TODO: Extend
        self.instance.handle(msg, argv)
      end

      def self.handles
        @handles or []
      end

    end

  end
end
