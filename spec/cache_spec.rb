require 'cache'

describe Cache do

	let! (:cache) { Cache.new 64 } # 64 bytes cache

	it { is_expected.to respond_to :get }
	it { is_expected.to respond_to :set }
	it { is_expected.to respond_to :key? }
	it { is_expected.to respond_to :[]= }
	it { is_expected.to respond_to :[] }
	it { is_expected.to respond_to :delete }
	it { is_expected.to respond_to :touch }
	it { is_expected.not_to respond_to :evict }

	def get_rand_string
		[*(:a..:z)].shuffle[0,8].join
	end

	def get_rand_char
		(65+rand(26)).chr
	end

	let! (:key) { get_rand_char }
	let! (:val) { get_rand_string }
	let! (:flags) { get_rand_string }
	let (:exptime) {Time.now.to_i+1}

	describe "#new" do
		it "returns an instance of Cache" do
			expect(cache).to be_an_instance_of Cache
		end
	end


	describe "#set" do

		it "sets value" do
			cache.set(key, val,nil,nil,nil)
			expect(cache.get(key)[:data]).to eq val
		end

		it "changes previous value" do
			cache.set(key, val,nil,nil,nil)

			rand_value=get_rand_string

			cache.set(key, rand_value,nil,nil,nil)
			expect(cache.get(key)[:data]).to eq rand_value
		end

		it "changes exptime" do
			cache.set(key, val,nil,nil,nil)

			cache.set(key, nil, nil, exptime, nil)
			expect(cache.get(key)[:exptime]).to eq exptime
		end

		it "changes flags" do
			cache.set(key, nil,nil,nil,flags)

			rand_flags=get_rand_string

			cache.set(key, nil, nil, nil, rand_flags)
			expect(cache.get(key)[:flags]).to eq rand_flags
		end

	end

	describe "#get" do

		context "with key in cache" do
			context "and with exptime" do
				before  do
					cache.set(key, val,nil,exptime,flags)
				end

				let! (:saved_data) { cache.get(key) }

				it "returns the stored value" do
					expect(saved_data[:data]).to eq val
				end

				it "returns the stored flags" do
					expect(saved_data[:flags]).to eq flags
				end

				it "returns the stored bytes" do
					expect(saved_data[:bytes]).to eq val.bytes.length
				end

				it "returns the stored exptime" do
					expect(saved_data[:exptime]).to eq exptime
				end

				it "returns valid cas" do
					cache.set(key, val,nil,exptime,flags)
					cache.set(key, val,nil,exptime,flags)

					expect(cache.get(key)[:cas]).to be 3
				end

				it "expires after exptime passed", :slow => true do
					sleep 1
					expect(cache.get(key)).to be nil
				end

			end

			context "and without exptime" do

				before  do
					cache.set(key, val,nil,nil,flags)
				end

				let! (:saved_data) { cache.get(key) }

				it "returns the stored value" do
					expect(saved_data[:data]).to eq val
				end

				it "returns the stored flags" do
					expect(saved_data[:flags]).to eq flags
				end

				it "returns the stored bytes" do
					expect(saved_data[:bytes]).to eq val.bytes.length
				end

				it "returns the stored exptime" do
					expect(saved_data[:exptime]).to eq 0
				end

				it "returns valid cas" do
					cache.set(key, val,nil,nil, flags)
					cache.set(key, val,nil,nil, flags)

					expect(cache.get(key)[:cas]).to be 3
				end

			end


		end


		context "without key in cache" do

			it "returns nil" do
				val = cache.get(key)
				expect(val).to be_nil
			end

		end

	end

	describe "#key?" do
		context "with key in cache" do
			before do
				cache.set(key, val)
			end
			it "returns true" do
				expect(cache.key?(key)).to be true
			end
		end
		context "without key in cache" do
			it "returns false" do
				expect(cache.key?(key)).to be false
			end
		end
	end

	describe "#delete" do
		context "with key in cache" do
			before do
				cache.set(key, val,nil,exptime,flags)
			end
			it "expires the data" do
				cache.delete(key)
				expect(cache.get(key)).to be nil
			end
		end
		context "without key in cache" do
			it "takes no action" do
				expect(cache.get(key)).to be nil
			end
		end
	end

	describe "#touch" do
		context "with key in cache" do
			before do
				cache.set(key, val, nil, 0, flags)
			end
			it "changes exptime" do
				cache.touch(key, exptime)
				expect(cache.get(key)[:exptime]).to eq exptime
			end
		end
		context "without key in cache" do
			it "takes no action" do
				expect(cache.get(key)).to be nil
			end
		end
	end

end
