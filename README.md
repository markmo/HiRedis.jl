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


    julia> Pkg.add("https://github.com/markmo/Hiredis.jl.git")

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

[![Build Status](https://travis-ci.org/markmo/Hiredis.jl.svg?branch=master)](https://travis-ci.org/markmo/Hiredis.jl)
