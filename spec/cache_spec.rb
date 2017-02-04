require 'memcached/cache'

def get_random_string(size = 8) # :nodoc: all
  return unless (size = Integer(size))
  output = []
  size.times do
    output << (rand(33..126)).chr
  end
  output.join
end

describe Memcached::Cache do
  # 64 bytes cache with max key size of 32 bytes
  let!(:cache) { Memcached::Cache.new(64, 32) }

  it { is_expected.to respond_to :get }
  it { is_expected.to respond_to :set }
  it { is_expected.to respond_to :key? }
  it { is_expected.to respond_to :[]= }
  it { is_expected.to respond_to :[] }
  it { is_expected.to respond_to :delete }
  it { is_expected.to respond_to :touch }
  it { is_expected.to respond_to :keys }
  it { is_expected.to respond_to :size }
  it { is_expected.to respond_to :max_key_size }
  it { is_expected.not_to respond_to :evict }


  let!(:key) { get_random_string(1) }
  let!(:val) { get_random_string(8) }
  let!(:flags) { get_random_string(8) }
  let!(:exptime) { Time.now.to_i + 1 }

  describe '#new' do
    it 'returns an instance of Memcached::Cache' do
      expect(cache).to be_an_instance_of Memcached::Cache
    end

    it 'shifts max_key_size to size it max_key_size is greater than size' do
      cache = Memcached::Cache.new(64, 128)
      expect(cache.max_key_size).to eq 64
    end

    it 'copies size to max_key_size if max_key_size isn\'t given' do
        cache = Memcached::Cache.new(64, 128)
      expect(cache.max_key_size).to eq cache.size
    end
  end

  describe '#set' do
    it 'sets value' do
      cache.set(key,:val => val)
      expect(cache.get(key)[:val]).to eq val
    end

    it 'changes previous value' do
      cache.set(key, :val => val)

      rand_value =  get_random_string(8)
      cache.set(key, :val => rand_value)
      expect(cache.get(key)[:val]).to eq rand_value
    end

    it 'changes exptime' do
      cache.set(key, :val => val)

      cache.set(key, :val => val, :exptime => exptime)
      expect(cache.get(key)[:exptime]).to eq exptime
    end

    it 'changes flags' do
      cache.set(key, :flags => flags)

      rand_flags = get_random_string(8)

      cache.set(key, :flags => rand_flags)
      expect(cache.get(key)[:flags]).to eq rand_flags
    end

    context 'when the cache is full' do
      before :each do
        (1..8).each do |k|
          cache[k]=get_random_string
        end
      end

      it 'deletes the least used key' do
        cache[9]=get_random_string
        expect(cache.keys).not_to include(1)
      end

      it 'deletes multiple old keys if necessary' do
        cache[9]=get_random_string(16)
        expect(cache.keys).not_to include(1)
        expect(cache.keys).not_to include(2)
      end
    end

    context 'when the data is bigger than max_key_size' do
      it 'raises a NoMemoryError exception' do
        expect{
          cache[:a] = get_random_string(65)
        }.to raise_error NoMemoryError
      end
    end
  end

  describe '#get' do
    context 'with key in cache' do
      context 'and with exptime' do
        before do
          cache.set(key, :val => val, :exptime => exptime, :flags => flags)
        end

        let!(:saved_data) { cache.get(key) }

        it 'returns the stored value' do
          expect(saved_data[:val]).to eq val
        end

        it 'returns the stored flags' do
          expect(saved_data[:flags]).to eq flags
        end

        it 'returns the stored bytes' do
          expect(saved_data[:bytes]).to eq val.bytes.length
        end

        it 'returns the stored exptime' do
          expect(saved_data[:exptime]).to eq exptime
        end

        it 'returns valid cas' do
          cache.set(key, :val => val)
          cache.set(key, :val => val)

          expect(cache.get(key)[:cas]).to be 3
        end

        it 'expires after exptime', slow: true do
          sleep 1
          expect(cache.get(key)).to be nil
        end
      end

      context 'and without exptime' do
        before do

          cache.set(key, :val => val, :flags => flags)
        end

        let!(:saved_data) { cache.get(key) }

        it 'returns the stored value' do
          expect(saved_data[:val]).to eq val
        end

        it 'returns the stored flags' do
          expect(saved_data[:flags]).to eq flags
        end

        it 'returns the stored bytes' do
          expect(saved_data[:bytes]).to eq val.bytes.length
        end

        it 'returns the stored exptime' do
          expect(saved_data[:exptime]).to eq 0
        end

        it 'returns valid cas' do
          cache.set(key, :val => val)
          cache.set(key, :val => val)

          expect(cache.get(key)[:cas]).to be 3
        end
      end
    end

    context 'without key in cache' do
      it 'returns nil' do
        val = cache.get(key)
        expect(val).to be_nil
      end
    end
  end

  describe '#key?' do
    context 'with key in cache' do
      before do
        cache.set(key, :val => val)
      end
      it 'returns true' do
        expect(cache.key?(key)).to be true
      end
    end
    context 'without key in cache' do
      it 'returns false' do
        expect(cache.key?(key)).to be false
      end
    end
  end

  describe '#delete' do
    context 'with key in cache' do
      before do
        cache.set(key, :val => val, :exptime => exptime, :flags => flags)
      end
      it 'expires the data' do
        cache.delete(key)
        expect(cache.get(key)).to be nil
      end
    end
    context 'without key in cache' do
      it 'takes no action' do
        expect(cache.get(key)).to be nil
      end
    end
  end

  describe '#touch' do
    context 'with key in cache' do
      before do
        cache.set(key, :val => val, :exptime => 0, :flags => flags)
      end
      it 'changes exptime' do
        cache.touch(key, exptime)
        expect(cache.get(key)[:exptime]).to eq exptime
      end
    end
    context 'without key in cache' do
      it 'takes no action' do
        expect(cache.get(key)).to be nil
      end
    end
  end

  describe '#keys' do
    before :each do
      @keys = [:a, :b, :c, :d, :e, :f, :g, :h]
      keys_shuffled = @keys.shuffle
      keys_shuffled.each do |k|
        cache[k] = get_random_string
      end
      @first = keys_shuffled[0]
      @last = keys_shuffled[-1]
    end
    it 'returns used keys' do
      cache_keys = cache.keys
      expect(cache_keys.length).to eq @keys.length
      expect(cache_keys.all? {|k| @keys.include? k}).to be true
    end
    it 'returns the last used key at the end of the array' do
      expect(cache.keys[-1]).to eq @last
    end

    it 'returns the least used key at the beggining of the array' do
      expect(cache.keys[0]).to eq @first
    end
  end

  describe "#size" do
    it 'returns the size of the cache' do
      expect(cache.size).to eq 64
    end
  end
  describe "#max_key_size" do
    it 'returns the max size per key of the cache' do
      expect(cache.max_key_size).to eq 32
    end
  end
end
