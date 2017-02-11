Memcached for Ruby
===

This is an implementation of the Memcached's protocol 100% written in Ruby.

### How to use

You can start the server right from the shell or directly from Ruby

#### Shell
```bash
 $ bin/memcached -p 11211 -S 4gb -s 1mb
```
As you can see there are several options available for you to use, you can see them by using the `--help` option but they will be explained here too.

 - `-p`: The port were the server should wait for connections. If the port 0 is given a random port will be provided by your operative system. Defaults to 11211
 - `-S`: The size of the cache in bytes. You can use values like `1G`, `128kb`, `64` etc. Defaults to 1mb
 - `-s`: The maximum size of a single key. Defaults to `-S`
 - `-v`: Shows more information about what happens in the server

#### Ruby

```ruby
require 'memcached'
cache = Memcached::Cache.new(1024*64, 1024) # size, maxKeySize
memcached = Memcached::Server.new(11211, cache) # port, cache
memached.start
```
If you want to start a Memcached server from the Ruby source code you have to create a `Memcached::Cache` object, the first parameter is the size in bytes of the cache and the second the size of each key.

Then this cache object has to be attached to a new `Memcached::Server` object which first parameter is the port where the server will be listening for connections and the second parameter the cache object you want to attach.

After that you only have to use the #start method on your newly created Memcached server and it will be up and running.
