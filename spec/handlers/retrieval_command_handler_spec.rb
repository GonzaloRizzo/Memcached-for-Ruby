require 'memcached/handlers/retrieval_command_handler'
require 'memcached/cache'
require 'socket'
require 'memcached/utils'

describe Memcached::Handlers::RetrievalCommandHandler do
  it 'should respond to #handle' do
    expect(described_class).to respond_to :handle
  end

  it 'should respond to #handles' do
    expect(described_class).to respond_to :handles
  end

  let!(:cache) { Memcached::Cache.new(64, 32) }


  describe '#handles' do
    it 'should handle the get and gets command' do
      expect(described_class.handles).to eq [:get, :gets]
    end
  end

  describe "#handler" do
    before :each do
      @client, @server = UNIXSocket.pair

      @lengths={}
      @texts={}
      @flags={}

      # Generates random data
      @lengths[:a] = rand(5..20)
      @texts[:a] = Memcached::Utils.random_string(@lengths[:a])
      @flags[:a] = rand(10000000..99999999)

      @lengths[:b] = rand(5..20)
      @texts[:b] = Memcached::Utils.random_string(@lengths[:b])
      @flags[:b] = rand(10000000..99999999)

      @lengths[:c] = rand(5..20)
      @texts[:c] = Memcached::Utils.random_string(@lengths[:c])
      @flags[:c] = rand(10000000..99999999)

      # Stores data

      cache.set("a", flags: @flags[:a], val: @texts[:a])
      cache.set("b", flags: @flags[:b], val: @texts[:b])
      cache.set("c", flags: @flags[:c], val: @texts[:c])

    end

    describe 'get' do
      context 'when data is stored' do
        it 'returns single stored data' do

          # Request the data stored on "a"
          described_class.handle("get",  {
            cache: cache,
            client: @server,
            argv: ["a"]
            })

          # Reads the answer and parses the response
          header_token, key, flag, length  = @client.gets("\r\n").split
          length = Integer(length)

          # Resolves header expectations
          expect(header_token).to eq "VALUE"
          expect(key).to eq "a"
          expect(flag).to eq @flags[:a].to_s
          expect(length).to eq @lengths[:a]
          expect(length).to be_an_instance_of Integer

          # Requests data
          data = @client.read length + 2

          # Resolves data expectations
          expect(data[-2,2]).to eq "\r\n"
          expect(data.chomp!).to eq @texts[:a]


          expect( @client.gets("\r\n")).to eq "END\r\n"
        end

        it 'returns multiple stored data' do
          # Requests the stored values of "a" "b" and "c"
          described_class.handle("get",  {
            cache: cache,
            client: @server,
            argv: ["a", "b", "c"]
            })

          keys = ["a", "b", "c"]
          until (msg = @client.gets("\r\n")) == "END\r\n"

            # Removes a key from the array of keys to expect
            current_key = keys.shift

            # Parses response
            header_token, key, flag, length  = msg.split
            length = Integer(length)

            # Resolves header expectations
            expect(header_token).to eq "VALUE"
            expect(key).to eq current_key
            expect(flag).to eq @flags[current_key.to_sym].to_s
            expect(length).to eq @lengths[current_key.to_sym]
            expect(length).to be_an_instance_of Integer

            # Requests data
            data = @client.read length + 2

            # Resolves data expectations
            expect(data[-2,2]).to eq "\r\n"
            expect(data.chomp!).to eq @texts[current_key.to_sym]
          end
          expect(msg).to eq "END\r\n"
        end

      end

      context 'when data is not stored' do
        it 'returns "END"' do
          described_class.handle("get",  {
            cache: cache,
            client: @server,
            argv: ["z"]
            })
          expect(@client.gets("\r\n")).to eq "END\r\n"
        end
      end

    end

    describe 'gets' do
      context 'when data is stored' do
        it 'returns single stored data' do

          # Request the data stored on "a"
          described_class.handle("gets",  {
            cache: cache,
            client: @server,
            argv: ["a"]
            })

          # Reads the answer and parses the response
          header_token, key, flag, length, cas  = @client.gets("\r\n").split
          length = Integer(length)
          cas = Integer(cas)

          # Resolves header expectations
          expect(header_token).to eq "VALUE"
          expect(key).to eq "a"
          expect(flag).to eq @flags[:a].to_s
          expect(length).to eq @lengths[:a]
          expect(length).to be_an_instance_of Integer
          expect(cas).to be_an_instance_of Integer
          expect(cas).to eq 1
          # Requests data
          data = @client.read length + 2

          # Resolves data expectations
          expect(data[-2,2]).to eq "\r\n"
          expect(data.chomp!).to eq @texts[:a]


          expect( @client.gets("\r\n")).to eq "END\r\n"
        end

        it 'returns multiple stored data' do
          # Requests the stored values of "a" "b" and "c"
          described_class.handle("gets",  {
            cache: cache,
            client: @server,
            argv: ["a", "b", "c"]
            })

          keys = ["a", "b", "c"]
          until (msg = @client.gets("\r\n")) == "END\r\n"

            # Removes a key from the array of keys to expect
            current_key = keys.shift

            # Parses response
            header_token, key, flag, length, cas  = msg.split
            length = Integer(length)
            cas = Integer(cas)

            # Resolves header expectations
            expect(header_token).to eq "VALUE"
            expect(key).to eq current_key
            expect(flag).to eq @flags[current_key.to_sym].to_s
            expect(length).to eq @lengths[current_key.to_sym]
            expect(length).to be_an_instance_of Integer
            expect(cas).to be_an_instance_of Integer
            expect(cas).to eq 1 if current_key == :a
            expect(cas).to eq 2 if current_key == :b
            expect(cas).to eq 3 if current_key == :c

            # Requests data
            data = @client.read length + 2

            # Resolves data expectations
            expect(data[-2,2]).to eq "\r\n"
            expect(data.chomp!).to eq @texts[current_key.to_sym]
          end
          expect(msg).to eq "END\r\n"
        end

      end

      context 'when data is not stored' do
        it 'returns "END"' do
          described_class.handle("gets",  {
            cache: cache,
            client: @server,
            argv: ["z"]
            })
          expect(@client.gets("\r\n")).to eq "END\r\n"
        end
      end
    end
  end



end
