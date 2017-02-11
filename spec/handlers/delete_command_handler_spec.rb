require 'memcached/handlers/delete_command_handler'
require 'memcached/cache'
require 'socket'
require 'memcached/utils'

describe Memcached::Handlers::DeleteCommandHandler do

    it 'should respond to #handle' do
      expect(described_class).to respond_to :handle
    end

    it 'should respond to #handles' do
      expect(described_class).to respond_to :handles
    end

    let!(:cache) { Memcached::Cache.new(64, 32) }

    describe '#handles' do
      it 'should handle the delete command' do
        expect(described_class.handles).to eq [:delete]
      end
    end

    describe "#handle" do
      before :each do
        @client, @server = UNIXSocket.pair

        cache["a"] = Memcached::Utils.random_string
      end

      context 'when data is stored' do
        it 'deletes the data' do
          described_class.handle("delete",  {
            cache: cache,
            client: @server,
            argv: ["a"]
            })
          expect(@client.gets("\r\n")).to eq "DELETED\r\n"
        end
      end
      context 'when data is not stored' do
        it 'returns "NOT_FOUND' do
          described_class.handle("delete",  {
            cache: cache,
            client: @server,
            argv: ["z"]
            })
          expect(@client.gets("\r\n")).to eq "NOT_FOUND\r\n"
        end
      end

    end
end
