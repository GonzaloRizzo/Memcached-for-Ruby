require "memcached/router"



describe Memcached::Router do

  # 64 bytes cache with max key size of 32 bytes
  let!(:router) { Memcached::Router.new }

  it { is_expected.to respond_to :route }
  it { is_expected.to respond_to :register }

  describe "#new" do
    it 'returns an instance of Memcached::Router' do
      expect(router).to be_an_instance_of Memcached::Router
    end
  end

  describe "#register" do
    it 'links a callback to a single command' do

      string = "This is a test!"

      router.register(:foo) do
        print string
      end

      expect {
        router.route("foo")
      }.to output(string).to_stdout

    end

    it 'links a single callback to multiple commands' do

      string = "This is a test!"
      router.register(:foo, :bar, :baz) do
        print string
      end

      expect {
        router.route("foo")
      }.to output(string).to_stdout

      expect {
        router.route("bar")
      }.to output(string).to_stdout

      expect {
        router.route("baz")
      }.to output(string).to_stdout

    end


    context 'with no block given' do
      it 'returns a LocalJumpError' do
        expect {
          router.register
        }.to raise_error LocalJumpError, "No block given"
      end
    end

  end

  describe "#route" do
    before :each do
      router.register(:sum, :mul) do |cmd, data|
        argv = data[:argv] if data

        if cmd == "sum"
          print Integer(argv[0]) + Integer(argv[1])
        elsif cmd == "mul"
          print Integer(argv[0]) * Integer(argv[1])
        end

      end

      router.register(:print) do |_cmd, data|
        argv = data[:argv] if data
        print argv.join " "
      end
    end

    it "routes to a single matched handler" do
      expect {
        router.route("print this is a test!")
      }.to output("this is a test!").to_stdout
    end

    it 'routes to a multiple matched handler' do
      expect {
        router.route("sum 10 5")
      }.to output("15").to_stdout

      expect {
        router.route("mul 10 5")
      }.to output("50").to_stdout
    end

    context 'when got routed somewhere' do
      it 'returns true' do
        expect(router.route("print")).to be true
      end
    end

    context 'when could not get routed' do
      it 'returns false' do
        expect(router.route("printf")).to be false
      end
    end
  end

  describe "#routeable?" do
    before :each do
        router.register(:ping) do
          # pong
        end
    end

    context 'when message is routeable' do
      it 'returns true' do
        expect(router.routeable? "ping").to be true
      end
    end

    context 'when message is not routeable' do
      it 'returns false' do
        expect(router.routeable? "pong").to be false
      end
    end
  end
end
