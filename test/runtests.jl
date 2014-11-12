using HiRedis
using Base.Test

using Logging

Logging.configure(level=INFO)

start_session("127.0.0.1", 6379)

info("select db 2 for testing, flushdb")
selectdb(2)
flushdb()

info("test incr")
incr("fooincr")
incr("fooincr")
fooincr = incr("fooincr")
@test fooincr == 3

info("test set and get")
kvset("foo", "bar")
@test kvget("foo") == "bar"

info("test hset and hget")
hset("customer:1", "first_name", "Mark")
@test hget("customer:1", "first_name") == "Mark"

info("test hmset and hmget")
hmset("customer:1", "first_name", "Alice", "last_name", "Bean")
reply = hmget("customer:1", "first_name", "last_name")
@test reply[2] == "Bean"

info("test hgetall")
reply = hgetall("customer:1")
@test reply["last_name"] == "Bean"

info("test sadd and smembers")
sadd("account_keyset:1", 1)
sadd("account_keyset:1", 2)
sadd("account_keyset:1", 2)
sadd("account_keyset:1", 3)
@test length(smembers("account_keyset:1")) == 3

info("pipeline commands")
sadd("pipeline_test:1", "foo", pipeline=true)
sadd("pipeline_test:1", "bar", pipeline=true)
sadd("pipeline_test:1", "bar", pipeline=true)
sadd("pipeline_test:1", "baz", pipeline=true)
smembers("pipeline_test:1", pipeline=true)
replies = get_reply()
@test length(replies[5]) == 3

info("test pipelining using the @pipeline macro")
@pipeline begin
    incr("maz")
    incr("maz")
    incr("maz")
    kvget("maz")
end
replies = get_reply()
@test int(replies[4]) == 3

info("flushdb, select db 1")
flushdb()
selectdb(1)

end_session()
