require 'cache'

describe Cache do
  before :each do
    @cache=Cache.new(64) # 64 bytes cache
  end

  it { is_expected.to respond_to :get }
  it { is_expected.to respond_to :set }
  it { is_expected.to respond_to :key? }
  it { is_expected.to respond_to :[]= }
  it { is_expected.to respond_to :[] }
  it { is_expected.to respond_to :delete }
  it { is_expected.to respond_to :touch }
  it { is_expected.not_to respond_to :evict }


  describe "#new" do
    it "returns an instance of Cache" do
      expect(@cache).to be_an_instance_of Cache
    end
  end



  describe "#get" do

    let! (:rand_key) { (65+rand(26)).chr }

    context "with key in cache" do
      let! (:rand_val) { [*(:a..:z)].shuffle[0,8].join }

      before  do
        @cache.set(rand_key, rand_val)
      end

      let! (:saved_data) { @cache.get(rand_key) }

      it "returns the saved value" do
        expect(saved_data[:data]).to eq rand_val
      end


    end

    context "without key in cache" do

      it "returns nil" do
        val = @cache.get(rand_key)
          expect(val).to be_nil
      end

    end

  end

end
