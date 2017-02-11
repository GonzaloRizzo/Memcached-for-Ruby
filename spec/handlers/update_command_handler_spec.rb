require 'memcached/handlers/update_command_handler'
require 'memcached/cache'
require 'socket'
require 'memcached/utils'

describe Memcached::Handlers::UpdateCommandHandler do
  it 'should respond to #handle' do
    expect(described_class).to respond_to :handle
  end

  it 'should respond to #handles' do
    expect(described_class).to respond_to :handles
  end

  let!(:cache) { Memcached::Cache.new(64) }


  describe '#handles' do
    it 'should handle the set, add, replace, append, prepend, and cas command' do
      expect(described_class.handles).to eq [:set, :add, :replace, :append, :prepend, :cas]
    end
  end

  describe "#handle" do
    before :each do
      @client, @server = UNIXSocket.pair

      # Generates random data
      @length = rand(5..20)
      @text = Memcached::Utils.random_string(@length)
      @key = Memcached::Utils.random_string(1)
      @flag = rand(10000000..99999999)
      @exptime = Time.now.to_i + 1
    end

    describe 'set' do

      it 'stores random length data' do
        # Sends the data
        @client.sendmsg("#{@text}\r\n")
        described_class.handle("set",  {
          cache: cache,
          client: @server,
          argv: [@key, "0", "0", "#{@length}"]
          })

        # Verifies that the data was correctly stored
        expect(@client.gets("\r\n")).to eq "STORED\r\n"
      end

      it 'stores random length flags' do
        # Sends the data and the flags
        @client.sendmsg("#{@text}\r\n")
        described_class.handle("set",  {
          cache: cache,
          client: @server,
          argv: [@key, "#{@flag}", "0", "#{@length}"]
          })

        # Verifies that the data was correctly stored
        expect(@client.gets("\r\n")).to eq "STORED\r\n"
      end

      it 'stores expirable data' do
        # Sends the data and the flags
        @client.sendmsg("#{@text}\r\n")

        described_class.handle("set", {
          cache: cache,
          client: @server,
          argv: [@key, "0", "#{@exptime}", "#{@length}"]
          })

        # Verifies that the data was correctly stored
        expect(@client.gets("\r\n")).to eq "STORED\r\n"

        sleep 1

        # Verifies that the key has expired
        expect(cache[@key]).to eq nil
      end
    end

    describe "add" do

      context 'with key in cache' do
        before :each do
          cache[@key] = @text
        end
        it 'does not store the data' do
          @client.sendmsg("#{@text}\r\n")
          described_class.handle("add", {
            cache: cache,
            client: @server,
            argv: [@key, "0", "0", "#{@length}"]
            })


          expect(@client.gets("\r\n")).to eq "NOT_STORED\r\n"
        end
      end

      context 'without key in cache' do
        it 'stores the data' do
          @client.sendmsg("#{@text}\r\n")
          described_class.handle("add", {
            cache: cache,
            client: @server,
            argv: [@key, "0", "0", "#{@length}"]
            })

          expect(@client.gets("\r\n")).to eq "STORED\r\n"
        end
      end
    end

    describe "replace" do
      context 'with key in cache' do
        before :each do
          cache[@key] = @text
        end
        it 'stores the data'  do
          @client.sendmsg("#{@text}\r\n")
          described_class.handle("replace", {
            cache: cache,
            client: @server,
            argv: [@key, "0", "0", "#{@length}"]
            })
          expect(@client.gets("\r\n")).to eq "STORED\r\n"
        end
      end
      context 'without key in cache' do
        it 'does not store the data' do
          @client.sendmsg("#{@text}\r\n")
          described_class.handle("replace", {
            cache: cache,
            client: @server,
            argv: [@key, "0", "0", "#{@length}"]
            })
          expect(@client.gets("\r\n")).to eq "NOT_STORED\r\n"
        end
      end
    end

    describe "append" do
      context 'with key in cache' do
        before :each do
          cache[@key] = @text
        end
        it 'stores the data'  do
          @client.sendmsg("#{@text}\r\n")
          described_class.handle("append", {
            cache: cache,
            client: @server,
            argv: [@key, "0", "0", "#{@length}"]
            })
          expect(@client.gets("\r\n")).to eq "STORED\r\n"
        end
      end
      context 'without key in cache' do
        it 'does not store the data' do
          @client.sendmsg("#{@text}\r\n")
          described_class.handle("append", {
            cache: cache,
            client: @server,
            argv: [@key, "0", "0", "#{@length}"]
            })
          expect(@client.gets("\r\n")).to eq "NOT_STORED\r\n"
        end
      end
    end

    describe "prepend" do
      context 'with key in cache' do
        before :each do
          cache[@key] = @text
        end
        it 'stores the data'  do
          @client.sendmsg("#{@text}\r\n")
          described_class.handle("prepend", {
            cache: cache,
            client: @server,
            argv: [@key, "0", "0", "#{@length}"]
            })
          expect(@client.gets("\r\n")).to eq "STORED\r\n"
        end
      end
      context 'without key in cache' do
        it 'does not store the data' do
          @client.sendmsg("#{@text}\r\n")
          described_class.handle("prepend", {
            cache: cache,
            client: @server,
            argv: [@key, "0", "0", "#{@length}"]
            })
          expect(@client.gets("\r\n")).to eq "NOT_STORED\r\n"
        end
      end
    end

    describe "cas" do
      context 'with key in cache' do
        before :each do
          cache[@key] = @text
          cache[@key] = @text
        end

        context 'with valid cas' do
          it 'stores the data'  do
            @client.sendmsg("#{@text}\r\n")
            described_class.handle("cas", {
              cache: cache,
              client: @server,
              argv: [@key, "0", "0", "#{@length}",  "2"]
              })
            expect(@client.gets("\r\n")).to eq "STORED\r\n"
          end
        end

        context 'without valid cas' do
          it 'does not store the data' do
            @client.sendmsg("#{@text}\r\n")
            described_class.handle("cas", {
              cache: cache,
              client: @server,
              argv: [@key, "0", "0", "#{@length}",  "0"]
              })
            expect(@client.gets("\r\n")).to eq "EXISTS\r\n"
          end
        end

      end
      context 'without key in cache' do
        it 'does not store the data' do
          @client.sendmsg("#{@text}\r\n")
          described_class.handle("cas", {
            cache: cache,
            client: @server,
            argv: [@key, "0", "0", "#{@length}",  "5"]
            })
          expect(@client.gets("\r\n")).to eq "NOT_FOUND\r\n"
        end
      end
    end
  end

end
