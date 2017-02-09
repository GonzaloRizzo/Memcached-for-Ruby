require 'singleton'
module Memcached
  module Handlers

    class BaseHandler
      include Singleton

      @handles = []

      def handle(_msg, _data)
        nil
      end

      def self.handle(msg, data=nil) #TODO: Extend
        self.instance.handle(msg, data)
      end

      def self.handles
        @handles or []
      end

    end

  end
end
