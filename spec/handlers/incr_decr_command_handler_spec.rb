require 'memcached/handlers/incr_decr_command_handler'
require 'memcached/cache'
require 'socket'
require 'memcached/utils'

describe Memcached::Handlers::IncrDecrCommandHandler do
  it 'should respond to #handle' do
    expect(described_class).to respond_to :handle
  end

  it 'should respond to #handles' do
    expect(described_class).to respond_to :handles
  end

  let!(:cache) { Memcached::Cache.new(64, 32) }

  describe '#handles' do
    it 'should handle the incr and decr command' do
      expect(described_class.handles).to eq [:incr, :decr]
    end
  end

  describe "#handle" do
    before :each do
      @client, @server = UNIXSocket.pair
      @text = 5
      @step = rand(0..9)
      cache["a"] = @text
    end

    describe 'incr' do
      context 'when data is stored' do
        it 'increments value by step' do
          described_class.handle("incr",  {
            cache: cache,
            client: @server,
            argv: ["a", "#{@step}"]
            })
          expect(Integer(@client.gets("\r\n"))).to eq @text + @step
        end
      end

      context 'when data is not stored' do
        it 'returns "NOT_FOUND"' do
          described_class.handle("incr",  {
            cache: cache,
            client: @server,
            argv: ["z", "#{@step}"]
            })
          expect(@client.gets("\r\n")).to eq "NOT_FOUND\r\n"
        end
      end

      context 'when data is not a number' do
        before :each do
          cache["a"] = Memcached::Utils.random_string
        end

        it 'returns CLIENT_ERROR' do
          described_class.handle("incr",  {
            cache: cache,
            client: @server,
            argv: ["a", "#{@step}"]
            })
          expect(@client.gets("\r\n")).to eq "CLIENT_ERROR cannot increment or decrement non-numeric value\r\n"
        end
      end

      context 'when step is not a number' do
        before :each do
          @step = "a"
        end

        it 'returns CLIENT_ERROR' do
          described_class.handle("incr",  {
            cache: cache,
            client: @server,
            argv: ["a", "#{@step}"]
            })
          expect(@client.gets("\r\n")).to eq "CLIENT_ERROR invalid numeric delta argument\r\n"
        end
      end
    end


    describe 'decr' do
      context 'when data is stored' do
        it 'decrements value by step' do
          described_class.handle("decr",  {
            cache: cache,
            client: @server,
            argv: ["a", "#{@step}"]
            })
          expect(Integer(@client.gets("\r\n"))).to eq @text - @step
        end
      end

      context 'when data is not stored' do
        it 'returns "NOT_FOUND"' do
          described_class.handle("decr",  {
            cache: cache,
            client: @server,
            argv: ["z", "#{@step}"]
            })
          expect(@client.gets("\r\n")).to eq "NOT_FOUND\r\n"
        end
      end

      context 'when data is not a number' do
        before :each do
          cache["a"] = Memcached::Utils.random_string
        end

        it 'returns "CLIENT_ERROR"' do
          described_class.handle("decr",  {
            cache: cache,
            client: @server,
            argv: ["a", "#{@step}"]
            })
          expect(@client.gets("\r\n")).to eq "CLIENT_ERROR cannot increment or decrement non-numeric value\r\n"
        end
      end

      context 'when step is not a number' do
        before :each do
          @step = "a"
        end

        it 'returns "CLIENT_ERROR"' do
          described_class.handle("decr",  {
            cache: cache,
            client: @server,
            argv: ["a", "#{@step}"]
            })
          expect(@client.gets("\r\n")).to eq "CLIENT_ERROR invalid numeric delta argument\r\n"
        end
      end
    end










  end
end
