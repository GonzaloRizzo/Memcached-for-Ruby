require 'memcached/handlers/touch_command_handler'
require 'memcached/cache'
require 'socket'
require 'memcached/utils'

describe Memcached::Handlers::TouchCommandHandler do
  it 'should respond to #handle' do
    expect(described_class).to respond_to :handle
  end

  it 'should respond to #handles' do
    expect(described_class).to respond_to :handles
  end

  let!(:cache) { Memcached::Cache.new(64, 32) }


  describe '#handles' do
    it 'should handle the touch command' do
      expect(described_class.handles).to eq [:touch]
    end
  end

  describe "#handle" do

    before :each do
      @client, @server = UNIXSocket.pair

      @text = Memcached::Utils.random_string(rand(5..20))
      @key = Memcached::Utils.random_string(1)
      @exptime = Time.now.to_i + 1

      cache[@key] = @text

    end

    describe "touch" do
      context 'when data is stored' do
        it 'changes exptime' do
          described_class.handle("touch",  {
            cache: cache,
            client: @server,
            argv: [@key, "#{@exptime}"]
            })

          expect(@client.gets("\r\n")).to eq "TOUCHED\r\n"

          sleep 1

          # Verifies that the key has expired
          expect(cache[@key]).to eq nil
        end
      end
      context 'when data is not stored' do
        it 'returns "NOT_FOUND' do
          described_class.handle("touch",  {
            cache: cache,
            client: @server,
            argv: ["z", "#{@exptime}"]
            })
          expect(@client.gets("\r\n")).to eq "NOT_FOUND\r\n"
        end
      end
    end

  end
end
