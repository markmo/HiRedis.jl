[![Build Status](https://travis-ci.org/markmo/Hiredis.jl.svg?branch=master)](https://travis-ci.org/markmo/Hiredis.jl)

# Hiredis

Julia Redis client, which wraps the hiredis C library.

[hiredis](https://github.com/redis/hiredis) is a C client library for the Redis database. [Redis](http://redis.io/) is an open source, BSD licensed, advanced key-value cache and store. It is often referred to as a data structure server since keys can contain strings, hashes, lists, sets, sorted sets, bitmaps and hyperloglogs. It is also referred to as a blazingly fast in-memory database. hiredis is developed by the same author as Redis.

Hiredis.jl provides a Julia client that interfaces with Redis through hiredis. This approach was chosen to leverage the stability and performance of hiredis.

## Install

Hiredis.jl has a dependency on the hiredis C library. To install hiredis:

OS X using the Homebrew package manager

    brew install hiredis

Debian / Ubuntu

    sudo apt-get install libhiredis-dev

Red Hat / CentOS

    sudo yum install hiredis

CentOS requires the EPEL repository. It may need to be installed from source on RHEL.

From source

    git clone git://github.com/antirez/hiredis.git
    cd hiredis
    sudo make && make install

Hiredis.jl is also dependent on the following Julia packages:

* Logging.jl
* Docile.jl (documentation)

To install into the Julia environment:

    julia> Pkg.clone("https://github.com/markmo/Hiredis.jl.git")

## Usage

    using Hiredis
    start_session("127.0.0.1", 6379)

    kvset("foo", "bar")
    kvget("foo")

    hset("myhash", "field1", "Hello")
    hget("myhash", "field1")

    hmset("myhash", Dict(:field1 => "Hello", :field2 => "World"))
    hmgetall("myhash")

Commands can be pipelined using the @pipeline macro:

    @pipeline begin
        incr("maz")
        incr("maz")
        incr("maz")
        kvget("maz")
    end
    replies = get_reply()

Pipelining sends a batch of commands to Redis to be processed in bulk. It cuts down the number of network requests. In the example above, the commands are only sent when the output buffer is full or `get_reply` is called.

The following command set is currently supported by a specific function:

* session
  * start_session
  * end_session
* key-value store
  * kvset
  * kvget
  * incr
  * del
  * exists
  * getkeys
  * rdump
  * rtype
* hash sets
  * hset
  * hget
  * hmset
  * hmget
  * hgetall
  * hdel
  * hexists
  * hkeys
  * hvals
  * hlen
  * hincrby
* sets
  * sadd
  * smembers
  * sismember
  * scard
  * srem
  * sdiff
  * sinter
  * sunion
* management
  * selectdb
  * flushdb
  * flushall
* pipelining
  * @pipeline
  * get_reply
* generic
  * do_command
  * pipeline_command

Any command not specifically supported above can be executed using the generic functions, e.g.:

    do_command("LPUSH mylist value")                    # blocking command

    pipeline_command("ZADD mysortedset score member")   # pipelined command

## Alternatives

[Redis.jl](https://github.com/msainz/Redis.jl) is a pure Julia implementation. It supports a basic set of commands for the key-value data structure. It doesn't appear to support pipelining yet.