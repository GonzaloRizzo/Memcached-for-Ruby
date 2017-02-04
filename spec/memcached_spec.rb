require 'memcached'
require "json"

def get_random_string(size = 8) # :nodoc: all
  return unless (size = Integer(size))
  output = []
  size.times do
    output << (rand(33..126)).chr
  end
  output.join
end

describe Memcached::Server do
  # Lowers the log level
  Memcached::LOG.level = Logger::FATAL

  let!(:server) { Memcached::Server.new 0 } # 0 means pick a random port
  let!(:server_thread) { server.start }

  it { is_expected.to respond_to :start }
  it { is_expected.to respond_to :stop }
  it { is_expected.to respond_to :online? }
  it { is_expected.to respond_to :port= }

  describe '#new' do
    it 'returns an instance of Memcached::Server' do
      expect(server).to be_an_instance_of Memcached::Server
    end

  end

  describe '#start' do

    it 'returns the listening thread' do
      expect(server_thread).to be_an_instance_of Thread
    end

    it 'listens on #{server.port}' do
      expect(TCPSocket.new 'localhost', server.port).to be_an_instance_of TCPSocket
    end

  end

  describe '#stop' do
    it 'stops the server' do
      server.stop
      expect(server.online?).to be false
    end

    it 'closes open connections' do
      client = TCPSocket.new("localhost", server.port)
      server.stop
      expect(client.recv_nonblock 0).to eq ""
    end
  end

  describe '#online?' do
    context 'server is online' do
      it 'returns true' do
        expect(server.online?).to be true
      end
    end
    context 'server is offline' do
      before :each do
        server.stop
      end
      it 'returns false' do
        expect(server.online?).to be false
      end
    end
  end

  describe '#port=' do
    context 'server is online' do
      it 'raises an exaption' do
        port = rand(1025..9999)
        expect {
          server.port = port
        }.to raise_error  "Cannot change the port when the server is open"

      end
    end
    context 'server is offline' do
      before :each do
        server.stop
      end
      it 'changes the port' do
        port = rand(1025..9999)
        server.port=port
        server.start
        expect(server.port).to be port
      end
    end
  end

  describe '@tcp_server', tcp_server: true do

    let!(:client) { TCPSocket.new("localhost", server.port) }

    describe 'update commands' do

      before :each do
        # Generates random data
        @length = rand(5..20)
        @text = get_random_string(@length)
        @key = get_random_string(1)
        @flag = rand(10000000..99999999)
        @exptime = Time.now.to_i + 1
      end

      describe 'set' do

        it 'stores random length data' do
          # Sends the data
          client.sendmsg("set #{@key} 0 0 #{@length}\r\n")
          client.sendmsg("#{@text}\r\n")

          # Verifies that the data was correctly stored
          expect(client.gets("\r\n")).to eq "STORED\r\n"
        end

        it 'stores random length flags' do
          # Sends the data and the flags
          client.sendmsg("set #{@key} #{@flag} 0 #{@length}\r\n")
          client.sendmsg("#{@text}\r\n")

          # Verifies that the data was correctly stored
          expect(client.gets("\r\n")).to eq "STORED\r\n"
        end

        it 'stores expirable data' do
          # Sends the data and the flags
          client.sendmsg("set #{@key} 0 #{@exptime} #{@length}\r\n")
          client.sendmsg("#{@text}\r\n")

          # Verifies that the data was correctly stored
          expect(client.gets("\r\n")).to eq "STORED\r\n"

          sleep 1

          # Verifies that the key has expired
          client.sendmsg("get #{@key}\r\n")
          expect(client.gets("\r\n")).to eq "END\r\n"
        end
      end

      describe "add" do
        context 'with key in cache' do
          before :each do
            client.sendmsg("set #{@key} 0 0 #{@length} noreply\r\n")
            client.sendmsg("#{@text}\r\n")
          end
          it 'does not store the data' do
            client.sendmsg("add #{@key} 0 0 #{@length}\r\n")
            client.sendmsg("#{@text}\r\n")
            expect(client.gets("\r\n")).to eq "NOT_STORED\r\n"
          end
        end
        context 'without key in cache' do
          it 'stores the data' do
            client.sendmsg("add #{@key} 0 0 #{@length}\r\n")
            client.sendmsg("#{@text}\r\n")
            expect(client.gets("\r\n")).to eq "STORED\r\n"
          end
        end
      end

      describe "replace" do
        context 'with key in cache' do
          before :each do
            client.sendmsg("set #{@key} 0 0 #{@length} noreply\r\n")
            client.sendmsg("#{@text}\r\n")
          end
          it 'stores the data'  do
            client.sendmsg("replace #{@key} 0 0 #{@length}\r\n")
            client.sendmsg("#{@text}\r\n")
            expect(client.gets("\r\n")).to eq "STORED\r\n"
          end
        end
        context 'without key in cache' do
          it 'does not store the data' do
            client.sendmsg("replace #{@key} 0 0 #{@length}\r\n")
            client.sendmsg("#{@text}\r\n")
            expect(client.gets("\r\n")).to eq "NOT_STORED\r\n"
          end
        end
      end

      describe "append" do
        context 'with key in cache' do
          before :each do
            client.sendmsg("set #{@key} 0 0 #{@length} noreply\r\n")
            client.sendmsg("#{@text}\r\n")
          end
          it 'stores the data'  do
            client.sendmsg("append #{@key} 0 0 #{@length}\r\n")
            client.sendmsg("#{@text}\r\n")
            expect(client.gets("\r\n")).to eq "STORED\r\n"
          end
        end
        context 'without key in cache' do
          it 'does not store the data' do
            client.sendmsg("append #{@key} 0 0 #{@length}\r\n")
            client.sendmsg("#{@text}\r\n")
            expect(client.gets("\r\n")).to eq "NOT_STORED\r\n"
          end
        end
      end

      describe "prepend" do
        context 'with key in cache' do
          before :each do
            client.sendmsg("set #{@key} 0 0 #{@length} noreply\r\n")
            client.sendmsg("#{@text}\r\n")
          end
          it 'stores the data'  do
            client.sendmsg("prepend #{@key} 0 0 #{@length}\r\n")
            client.sendmsg("#{@text}\r\n")
            expect(client.gets("\r\n")).to eq "STORED\r\n"
          end
        end
        context 'without key in cache' do
          it 'does not store the data' do
            client.sendmsg("prepend #{@key} 0 0 #{@length}\r\n")
            client.sendmsg("#{@text}\r\n")
            expect(client.gets("\r\n")).to eq "NOT_STORED\r\n"
          end
        end
      end

      describe "cas" do
        context 'with key in cache' do
          before :each do
            client.sendmsg("set #{@key} 0 0 #{@length} noreply\r\n")
            client.sendmsg("#{@text}\r\n")

            client.sendmsg("set #{@key} 0 0 #{@length} noreply\r\n")
            client.sendmsg("#{@text}\r\n")
          end

          context 'with valid cas' do
            it 'stores the data'  do
              client.sendmsg("cas #{@key} 0 0 #{@length} 2\r\n")
              client.sendmsg("#{@text}\r\n")
              expect(client.gets("\r\n")).to eq "STORED\r\n"
            end
          end

          context 'without valid cas' do
            it 'does not store the data' do
              client.sendmsg("cas #{@key} 0 0 #{@length} 0\r\n")
              client.sendmsg("#{@text}\r\n")
              expect(client.gets("\r\n")).to eq "EXISTS\r\n"
            end
          end

        end
        context 'without key in cache' do
          it 'does not store the data' do
            client.sendmsg("cas #{@key} 0 0 #{@length} 5\r\n")
            client.sendmsg("#{@text}\r\n")
            expect(client.gets("\r\n")).to eq "NOT_FOUND\r\n"
          end
        end
      end
    end

    describe 'retrival comands' do
      before :each do
        @lengths={}
        @texts={}
        @flags={}

        # Generates random data
        @lengths[:a] = rand(5..20)
        @texts[:a] = get_random_string(@lengths[:a])
        @flags[:a] = rand(10000000..99999999)

        @lengths[:b] = rand(5..20)
        @texts[:b] = get_random_string(@lengths[:b])
        @flags[:b] = rand(10000000..99999999)

        @lengths[:c] = rand(5..20)
        @texts[:c] = get_random_string(@lengths[:c])
        @flags[:c] = rand(10000000..99999999)

        # Stores data
        client.sendmsg("set a #{@flags[:a]} 0 #{@lengths[:a]} noreply\r\n")
        client.sendmsg("#{@texts[:a]}\r\n")

        client.sendmsg("set b #{@flags[:b]} 0 #{@lengths[:b]} noreply\r\n")
        client.sendmsg("#{@texts[:b]}\r\n")

        client.sendmsg("set c #{@flags[:c]} 0 #{@lengths[:c]} noreply\r\n")
        client.sendmsg("#{@texts[:c]}\r\n")
      end
      describe 'get' do
        context 'when data is stored' do
          it 'returns single stored data' do

            # Request the data stored on "a"
            client.sendmsg("get a\r\n")

            # Reads the answer and parses the response
            header_token, key, flag, length  = client.gets("\r\n").split
            length = Integer(length)

            # Resolves header expectations
            expect(header_token).to eq "VALUE"
            expect(key).to eq "a"
            expect(flag).to eq @flags[:a].to_s
            expect(length).to eq @lengths[:a]
            expect(length).to be_an_instance_of Integer

            # Requests data
            data = client.read length + 2

            # Resolves data expectations
            expect(data[-2,2]).to eq "\r\n"
            expect(data.chomp!).to eq @texts[:a]


            expect( client.gets("\r\n")).to eq "END\r\n"
          end

          it 'returns multiple stored data' do
            # Requests the stored values of "a" "b" and "c"
            client.sendmsg("get a b c\r\n")

            keys = ["a", "b", "c"]
            until (msg = client.gets("\r\n")) == "END\r\n"

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
              data = client.read length + 2

              # Resolves data expectations
              expect(data[-2,2]).to eq "\r\n"
              expect(data.chomp!).to eq @texts[current_key.to_sym]
            end
            expect(msg).to eq "END\r\n"
          end

        end

        context 'when data is not stored' do
          it 'returns "END"' do
            client.sendmsg("get z\r\n")
            expect(client.gets("\r\n")).to eq "END\r\n"
          end
        end

      end

      describe 'gets' do
        context 'when data is stored' do
          it 'returns single stored data' do

            # Request the data stored on "a"
            client.sendmsg("gets a\r\n")

            # Reads the answer and parses the response
            header_token, key, flag, length, cas  = client.gets("\r\n").split
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
            data = client.read length + 2

            # Resolves data expectations
            expect(data[-2,2]).to eq "\r\n"
            expect(data.chomp!).to eq @texts[:a]


            expect( client.gets("\r\n")).to eq "END\r\n"
          end

          it 'returns multiple stored data' do
            # Requests the stored values of "a" "b" and "c"
            client.sendmsg("gets a b c\r\n")

            keys = ["a", "b", "c"]
            until (msg = client.gets("\r\n")) == "END\r\n"

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
              data = client.read length + 2

              # Resolves data expectations
              expect(data[-2,2]).to eq "\r\n"
              expect(data.chomp!).to eq @texts[current_key.to_sym]
            end
            expect(msg).to eq "END\r\n"
          end

        end

        context 'when data is not stored' do
          it 'returns "END"' do
            client.sendmsg("gets z\r\n")
            expect(client.gets("\r\n")).to eq "END\r\n"
          end
        end
      end
    end

    describe 'incr/decr commands' do
      before :each do
        @length = 1
        @text = 5
        @step = rand(0..9)
        client.sendmsg("set a 0 0 #{@length} noreply\r\n")
        client.sendmsg("#{@text}\r\n")
      end
      describe 'incr' do
        context 'when data is stored' do
          it 'increments value by step' do
            client.sendmsg("incr a #{@step}\r\n")
            expect(Integer(client.gets("\r\n"))).to eq @text + @step
          end
        end
        context 'when data is not stored' do
          it 'returns "NOT_FOUND"' do
            client.sendmsg("incr z #{@step}\r\n")
            expect(client.gets("\r\n")).to eq "NOT_FOUND\r\n"
          end
        end
        context 'when data is not a number' do
          before :each do
            @length = rand(5..20)
            @text = get_random_string(@length)
            client.sendmsg("set a 0 0 #{@length} noreply\r\n")
            client.sendmsg("#{@text}\r\n")
          end

          it 'returns CLIENT_ERROR' do
            client.sendmsg("incr a #{@step}\r\n")
            expect(client.gets("\r\n")).to eq "CLIENT_ERROR cannot increment or decrement non-numeric value\r\n"
          end
        end
        context 'when step is not a number' do
          before :each do
            @length = 1
            @step = "a"
            client.sendmsg("set a 0 0 #{@length} noreply\r\n")
            client.sendmsg("#{@text}\r\n")
          end

          it 'returns CLIENT_ERROR' do
            client.sendmsg("incr a #{@step}\r\n")
            expect(client.gets("\r\n")).to eq "CLIENT_ERROR invalid numeric delta argument\r\n"
          end
        end
      end
      describe 'decr' do
        context 'when data is stored' do
          it 'decrements value by step' do
            client.sendmsg("decr a #{@step}\r\n")
            expect(Integer(client.gets("\r\n"))).to eq @text - @step
          end
        end
        context 'when data is not stored' do
          it 'returns "NOT_FOUND"' do
            client.sendmsg("decr z #{@step}\r\n")
            expect(client.gets("\r\n")).to eq "NOT_FOUND\r\n"
          end
        end
        context 'when data is not a number' do
          before :each do
            @length = rand(5..20)
            @text = get_random_string(@length)
            client.sendmsg("set a 0 0 #{@length} noreply\r\n")
            client.sendmsg("#{@text}\r\n")
          end

          it 'returns "CLIENT_ERROR"' do
            client.sendmsg("decr a #{@step}\r\n")
            expect(client.gets("\r\n")).to eq "CLIENT_ERROR cannot increment or decrement non-numeric value\r\n"
          end
        end
        context 'when step is not a number' do
          before :each do
            @length = 1
            @step = "a"
            client.sendmsg("set a 0 0 #{@length} noreply\r\n")
            client.sendmsg("#{@text}\r\n")
          end

          it 'returns "CLIENT_ERROR"' do
            client.sendmsg("decr a #{@step}\r\n")
            expect(client.gets("\r\n")).to eq "CLIENT_ERROR invalid numeric delta argument\r\n"
          end
        end
      end
    end

    describe 'delete commands' do
      before :each do
        @length = rand(5..20)
        @text = get_random_string(@length)
        @key = get_random_string(1)
        client.sendmsg("set a 0 0 #{@length} noreply\r\n")
        client.sendmsg("#{@text}\r\n")
      end

      describe "delete" do
        context 'when data is stored' do
          it 'deletes the data' do
            client.sendmsg("delete a\r\n")
            expect(client.gets("\r\n")).to eq "DELETED\r\n"
          end
        end
        context 'when data is not stored' do
          it 'returns "NOT_FOUND' do
            client.sendmsg("delete z\r\n")
            expect(client.gets("\r\n")).to eq "NOT_FOUND\r\n"
          end
        end
      end
    end

    describe 'touch command' do
      before :each do
        @length = rand(5..20)
        @text = get_random_string(@length)
        @key = get_random_string(1)
        @exptime = Time.now.to_i + 1

        client.sendmsg("set #{@key} 0 0 #{@length} noreply\r\n")
        client.sendmsg("#{@text}\r\n")
      end
      describe "touch" do
        context 'when data is stored' do
          it 'changes exptime' do
            client.sendmsg("touch #{@key} #{@exptime}\r\n")

            expect(client.gets("\r\n")).to eq "TOUCHED\r\n"

            sleep 1

            # Verifies that the key has expired
            client.sendmsg("get #{@key}\r\n")
            expect(client.gets("\r\n")).to eq "END\r\n"
          end
        end
        context 'when data is not stored' do
          it 'returns "NOT_FOUND' do
            client.sendmsg("delete z\r\n")
            expect(client.gets("\r\n")).to eq "NOT_FOUND\r\n"
          end
        end
      end
    end





    it 'supports 10 concurrent connections', concurrency_test: true do
      client.close

      # Array of running threads
      thrs = []

      # Execute 10 threads
      10.times do
        # Add threads to the array
        thrs << Thread.new do

          # Creates a client for this connection
          client = TCPSocket.new("localhost", server.port)

          until Thread.current[:exit?]
            # Generates random data
            length = rand 8..50
            data = get_random_string(length)
            key = get_random_string

            # Sends random data
            client.sendmsg("set #{key} 0 0 #{length} noreply\r\n")
            client.sendmsg("#{data}\r\n")

            # Tries to retrive the data
            client.sendmsg("get #{key}\r\n")

            # Reads the answer and parses the response
            header_token, key, flag, length  = client.gets("\r\n").split
            length = Integer(length)
            flag = Integer(flag)

            # Resolves header expectations
            expect(header_token).to eq "VALUE"
            expect(key).to eq key
            expect(flag).to eq 0
            expect(length).to eq length
            expect(length).to be_an_instance_of Integer

            # Requests data
            data = client.read length + 2

            # Resolves data expectations
            expect(data[-2,2]).to eq "\r\n"
            expect(data.chomp!).to eq data
            expect( client.gets("\r\n")).to eq "END\r\n"
          end
          # Closes the connection
          client.close
        end
      end

      # waits 5 seconds and then requests all threads to finish
      sleep 5

      thrs.each do |t|
        t[:exit?]=true
        t.join
      end

    end

    after :each do
      server.stop
    end

  end
end
