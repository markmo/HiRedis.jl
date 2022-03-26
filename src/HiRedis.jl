# redis client in julia
# wraps the stable hiredis C library

module HiRedis

using Logging

logger = SimpleLogger(stdout, Logging.Warn)
global_logger(logger)

const REDIS_ERR = -1
const REDIS_OK = 0

const REDIS_REPLY_STRING = 1
const REDIS_REPLY_ARRAY = 2
const REDIS_REPLY_INTEGER = 3
const REDIS_REPLY_NIL = 4
const REDIS_REPLY_STATUS = 5
const REDIS_REPLY_ERROR = 6

global redisContext = 0
global pipelinedCommandCount = 0

struct RedisReadTask
    rtype::Int32
    elements::Int32
    idx::Int32
    obj::Ptr{Void}
    parent::Ptr{RedisReadTask}
    privdata::Ptr{Void}
end

function create_string(task::Ptr{RedisReadTask}, str::Ptr{Uint8}, len::Uint)
    # not implemented
    ret::Ptr{Void} = 0
    ret
end

function create_array(task::Ptr{RedisReadTask}, len::Int32)
    # not implemented
    ret::Ptr{Void} = 0
    ret
end

function create_integer(task::Ptr{RedisReadTask}, int::Int)
    # not implemented
    ret::Ptr{Void} = 0
    ret
end

function create_nil(task::Ptr{RedisReadTask})
    # not implemented
    ret::Ptr{Void} = 0
    ret
end

function free_object(obj::Ptr{Void})
    # not implemented
    ret::Void = 0
    ret
end

const create_string_c = cfunction(create_string, Ptr{Void}, (Ptr{RedisReadTask}, Ptr{Uint8}, Uint))

const create_array_c = cfunction(create_array, Ptr{Void}, (Ptr{RedisReadTask}, Int32))

const create_integer_c = cfunction(create_integer, Ptr{Void}, (Ptr{RedisReadTask}, Int))

const create_nil_c = cfunction(create_nil, Ptr{Void}, (Ptr{RedisReadTask},))

const free_object_c = cfunction(free_object, Void, (Ptr{Void},))

struct RedisReplyObjectFunctions
    create_string_c
    create_array_c
    create_integer_c
    create_nil_c
    free_object_c
end

struct RedisReader
    err::Int32
    errstr::Ptr{Uint8}
    buf::Ptr{Uint8}
    pos::Uint
    len::Uint
    maxbuf::Uint
    rstack::Array{RedisReadTask,1}
    ridx::Int32
    reply::Ptr{Void}
    fn::Ptr{RedisReplyObjectFunctions}
    privdata::Ptr{Void}
end

struct RedisContext
    err::Int32
    errstr::Ptr{Uint8}
    fd::Int32
    flags::Int32
    obuf::Ptr{Uint8}
    reader::Ptr{RedisReader}
end

struct RedisReply
    rtype::Int32                  # REDIS_REPLY_*
    integer::Uint64               # The integer when type is REDIS_REPLY_INTEGER
    len::Int32                    # Length of string
    str::Ptr{Uint8}               # Used for both REDIS_REPLY_ERROR and REDIS_REPLY_STRING
    elements::Uint                # number of elements, for REDIS_REPLY_ARRAY
    element::Ptr{Ptr{RedisReply}} # elements vector for REDIS_REPLY_ARRAY
end

function start_session(host::ASCIIString = "127.0.0.1", port::Int = 6379)
    global redisContext = ccall((:redisConnect, "libhiredis"), Ptr{RedisContext}, (Ptr{Uint8}, Int32), host, port)
end

function end_session()
    if redisContext != 0 # isdefined(:redisContext)
        ccall((:redisFree, "libhiredis"), Void, (Ptr{RedisContext},), redisContext::Ptr{RedisContext})
    end
end

"""Free memory allocated to objects returned from hiredis"""
function free_reply_object(redisReply)
    ccall((:freeReplyObject, "libhiredis"), Void, (Ptr{RedisReply},), redisReply)
end

"""
Appends commands to an output buffer. Pipelining is sending a batch of commands
to redis to be processed in bulk. It cuts down the number of network requests.
"""
function pipeline_command(command::ASCIIString)
    if redisContext == 0 # !isdefined(:redisContext)
        start_session()
    end
    debug(string("RedisClient.pipeline_command: ", command))
    global pipelinedCommandCount += 1
    ccall((:redisAppendCommand, "libhiredis"), Int32, (Ptr{RedisContext}, Ptr{Uint8}), redisContext::Ptr{RedisContext}, command)
end

"""
In a blocking context, this function first checks if there are unconsumed
replies to return and returns one if so. Otherwise, it flushes the output
buffer to the socket and reads until it has a reply.
"""
function call_get_reply(redisReply::Array{Ptr{RedisReply},1})
    ccall((:redisGetReply, "libhiredis"), Int32, (Ptr{RedisContext}, Ptr{Ptr{RedisReply}}), redisContext::Ptr{RedisContext}, redisReply)
end

"""
Calls call_get_reply until the pipelinedCommandCount is 0 or an error
is returned. Adds the results from each reply to an Array, then returns the
Array.
"""
function get_reply()
    redisReply = Array(Ptr{RedisReply},1)
    results = Any[]
    while pipelinedCommandCount::Int > 0 && call_get_reply(redisReply) == REDIS_OK
        push!(results, get_result(redisReply[1]))
        global pipelinedCommandCount -= 1
    end
    results
end

"""
Converts the reply object from hiredis into a String, int, or Array
as appropriate the the reply type.
"""
function get_result(redisReply::Ptr{RedisReply})
    r = unsafe_load(redisReply)
    if r.rtype == REDIS_REPLY_ERROR
        error(bytestring(r.str))
    end
    ret::Any = nothing
    if r.rtype == REDIS_REPLY_STRING
        ret = bytestring(r.str)
    elseif r.rtype == REDIS_REPLY_INTEGER
        ret = int(r.integer)
    elseif r.rtype == REDIS_REPLY_ARRAY
        n = int(r.elements)
        results = ASCIIString[]
        replies = pointer_to_array(r.element, n)
        for i in 1:n
            ri = unsafe_load(replies[i])
            push!(results, bytestring(ri.str))
        end
        ret = results
    end
    free_reply_object(redisReply)
    ret
end

"""Pipelines a block of ordinary blocking calls."""
macro pipeline(expr::Expr)
    Expr(:block, map(x ->
        begin
            if x.args[1] in names(HiRedis)
                args = copy(x.args)
                push!(args, Expr(:kw, :pipeline, true))
                Expr(x.head, args...)
            else
                x
            end
        end, filter(x -> typeof(x) == Expr, expr.args))...)
end

"""Issues a blocking command to hiredis."""
function do_command(command::ASCIIString)
    if redisContext == 0 # !isdefined(:redisContext)
#         error("redisContext not defined. Please call RedisClient.start_session.")
        start_session()
    end
    debug(string("RedisClient.do_command: ", command))
    redisReply = ccall((:redisvCommand, "libhiredis"), Ptr{RedisReply}, (Ptr{RedisContext}, Ptr{Uint8}), redisContext::Ptr{RedisContext}, command)
    get_result(redisReply)
end

"""Issues a blocking command to hiredis, accepting command arguments as an Array."""
function do_command{S<:Any}(argv::Array{S,1})
    if redisContext == 0 # !isdefined(:redisContext)
        start_session()
    end
    redisReply = ccall((:redisCommandArgv, "libhiredis"), Ptr{RedisReply}, (Ptr{RedisContext}, Int32, Ptr{Ptr{Uint8}}, Ptr{Uint}), redisContext::Ptr{RedisContext}, length(argv), argv, C_NULL)
    get_result(redisReply)
end

"""Switches between blocking and pipelined command execution according to flag."""
function docommand(cmd::ASCIIString, pipeline::Bool)
    (pipeline || (pipelinedCommandCount::Int > 0)) ? pipeline_command(cmd) : do_command(cmd)
end

# @doc "Set the string value of a key." Dict{Any,Any}(
#     :params => Dict(
#         :key           => "The key to set",
#         :value         => "The value to set",
#         :ex            => "Set the specified expire time, in seconds",
#         :px            => "Set the specified expire time, in milliseconds",
#         :pipeline      => "A flag to indicate that the command should be pipelined"
#     )) ->
"""
Set the string value of a key.

Params:

* key - The key to set
* value - The value to set
* ex - Set the specified expire time, in seconds
* px - Set the specified expire time, in milliseconds
* pipeline - A flag to indicate that the command should be pipelined
"""
function kvset(key::ASCIIString, value::Any; ex::Int=0, px::Int=0, pipeline::Bool=false)
    cmd = string("SET ", key, " ", value)
    if ex > 0
        cmd = string(cmd, " EX ", ex)
    elseif px > 0
        cmd = string(cmd, " PX ", ex)
    end
    docommand(cmd, pipeline)
end

"""Get the value of a key."""
function kvget(key::ASCIIString; pipeline::Bool=false)
    docommand(string("GET ", key), pipeline)
end

"""Increment the integer value of a key by one."""
function incr(key::ASCIIString; pipeline::Bool=false)
    docommand(string("INCR ", key), pipeline)
end

"""Increment the integer value of a key by the given amount."""
function incrby(key::ASCIIString, by::Int; pipeline::Bool=false)
    docommand(string("INCRBY ", key, " ", by), pipeline)
end

"""Delete a key."""
function del(key::ASCIIString)
    docommand(string("DEL ", key))
end

"""Determine if a key exists."""
function exists(key::ASCIIString)
    docommand(string("EXISTS ", key))
end

"""Find all keys matching the given pattern."""
function getkeys(pattern::ASCIIString)
    docommand(string("KEYS ", pattern))
end

"""Return a serialized version of the value stored at the specified key."""
function rdump(key::ASCIIString)
    docommand(string("DUMP ", key))
end

"""Determine the type stored at key."""
function rtype(key::ASCIIString)
    docommand(string("TYPE ", key))
end

"""Set the string value of a hash field."""
function hset(key::ASCIIString, attr_name::ASCIIString, attr_value::Any; pipeline::Bool=false)
    #TODO do_command(["HSET %s %s %s", key, attr_name, string(attr_value)])
    docommand(string("HSET ", key, " ", attr_name, " ", attr_value), pipeline)
end

"""Get the value of a hash field."""
function hget(key::ASCIIString, attr_name::ASCIIString; pipeline::Bool=false)
    docommand(string("HGET ", key, " ", attr_name), pipeline)
end

"""
Set multiple hash fields to multiple values. A variable number of arguments
follow key in `field` `value` format, e.g.:
    `hmset("myhash", "field1", "Hello", "field2", "World")`
"""
function hmset(key::ASCIIString, argv::Any...; pipeline::Bool=false)
    cmd = string("HMSET ", key)
    for arg in argv
        cmd = string(cmd, " ", string(arg))
    end
    docommand(cmd, pipeline)
end

"""
Set multiple hash fields to multiple values. Fields and values are provided
as an Array.
"""
function hmset{S<:Any}(key::ASCIIString, attrs::Array{S,1}; pipeline::Bool=false)
    cmd = string("HMSET ", key)
    for attr in attrs
        cmd = string(cmd, " ", string(attr))
    end
    docommand(cmd, pipeline)
end

"""
Set multiple hash fields to multiple values. Fields and values are provided
as a Dict.
"""
function hmset(key::ASCIIString, attrs::Dict{ASCIIString,Any}; pipeline::Bool=false)
    cmd = string("HMSET ", key)
    for (field, val) in attrs
        cmd = string(cmd, " ", field, " ", string(val))
    end
    docommand(cmd, pipeline)
end

"""
Get the values of all the given hash fields. Multiple fields are provided
as additional arguments.
"""
function hmget(key::ASCIIString, argv::ASCIIString...; pipeline::Bool=false)
    cmd = string("HMGET ", key)
    for arg in argv
        cmd = string(cmd, " ", arg)
    end
    docommand(cmd, pipeline)
end

"""
Get the values of all the given hash fields. Multiple fields are provided
as an Array.
"""
function hmget(key::ASCIIString, fields::Array{ASCIIString,1}; pipeline::Bool=false)
    cmd = string("HMGET ", key)
    for field in fields
        cmd = string(cmd, " ", field)
    end
    docommand(cmd, pipeline)
end

"""Get all the fields and values in a hash."""
function hgetall(key::ASCIIString)
    reply::Array{Any,1} = do_command(string("HGETALL ", key))
    n = length(reply)
    dict = Dict{ASCIIString,Any}()
    if n > 1 && mod(n, 2) == 0
        for i = 1:2:n
            dict[reply[i]] = reply[i + 1]
        end
    end
    dict
end

"""
Delete one or more hash fields. Multiple fields are provided
as additional arguments.
"""
function hdel(key::ASCIIString, argv::ASCIIString...; pipeline::Bool=false)
    cmd = string("HDEL ", key)
    for arg in argv
        cmd = string(cmd, " ", arg)
    end
    docommand(cmd, pipeline)
end

"""
Delete one or more hash fields. Multiple fields are provided
as an Array.
"""
function hdel(key::ASCIIString, fields::Array{ASCIIString,1}; pipeline::Bool=false)
    cmd = string("HDEL ", key)
    for field in fields
        cmd = string(cmd, " ", field)
    end
    docommand(cmd, pipeline)
end

"""Determine if a hash field exists."""
function hexists(key::ASCIIString, field::ASCIIString; pipeline::Bool=false)
    docommand(string("HEXISTS ", key, " ", field), pipeline)
end

"""Get all the fields in a hash."""
function hkeys(key::ASCIIString; pipeline::Bool=false)
    docommand(string("HKEYS ", key), pipeline)
end

"""Get all the values in a hash."""
function hvals(key::ASCIIString; pipeline::Bool=false)
    docommand(string("HVALS ", key), pipeline)
end

"""Get the number of fields in a hash."""
function hlen(key::ASCIIString; pipeline::Bool=false)
    docommand(string("HLEN ", key), pipeline)
end

"""Increment the integer value of a hash field by the given number."""
function hincrby(key::ASCIIString, field::ASCIIString, increment::Int; pipeline::Bool=false)
    docommand(string("HINCRBY ", key, " ", field, " ", increment), pipeline)
end

"""Increment the float value of a hash field by the given number."""
function hincrby(key::ASCIIString, field::ASCIIString, increment::Float64; pipeline::Bool=false)
    docommand(string("HINCRBYFLOAT ", key, " ", field, " ", increment), pipeline)
end

"""Add one or more members to a set."""
function sadd(key::ASCIIString, argv::Any...; pipeline::Bool=false)
    cmd = string("SADD ", key)
    for arg in argv
        if isa(arg, Array) || isa(arg, Range)
            for member in arg
                cmd = string(cmd, " ", string(member))
            end
        else
            cmd = string(cmd, " ", string(arg))
        end
    end
    docommand(cmd, pipeline)
end

"""Get all the members in a set."""
function smembers(key::ASCIIString; pipeline::Bool=false)
    docommand(string("SMEMBERS ", key), pipeline)
end

"""Determine if a given value is a member of a set."""
function sismember(key::ASCIIString, member::Any; pipeline::Bool=false)
    docommand(string("SISMEMBER ", key, " ", string(member)), pipeline)
end

"""Get the number of members in a set."""
function scard(key::ASCIIString; pipeline::Bool=false)
    docommand(string("SCARD ", key), pipeline)
end

"""
Remove one or more members from a set. Members are provided
as additional arguments.
"""
function srem(key::ASCIIString, argv::Any...; pipeline::Bool=false)
    cmd = string("SREM ", key)
    for arg in argv
        cmd = string(cmd, " ", string(arg))
    end
    docommand(cmd, pipeline)
end

"""
Remove one or more members from a set. Members are provided
as an Array.
"""
function srem{S<:Any}(key::ASCIIString, members::Array{S,1}; pipeline::Bool=false)
    cmd = string("SREM ", key)
    for member in members
        cmd = string(cmd, " ", string(member))
    end
    docommand(cmd, pipeline)
end

"""Subtract multiple sets. Multiple sets are provided as additional arguments."""
function sdiff(key::ASCIIString, argv::ASCIIString...; pipeline::Bool=false)
    cmd = string("SDIFF ", key)
    for arg in argv
        cmd = string(cmd, " ", arg)
    end
    docommand(cmd, pipeline)
end

"""Subtract multiple sets. Multiple sets are provided as an Array."""
function sdiff(keys::Array{ASCIIString,1}; pipeline::Bool=false)
    cmd = "SDIFF"
    for key in keys
        cmd = string(cmd, " ", key)
    end
    docommand(cmd, pipeline)
end

"""Intersect multiple sets. Multiple sets are provided as additional arguments."""
function sinter(key::ASCIIString, argv::ASCIIString...; pipeline::Bool=false)
    cmd = string("SINTER ", key)
    for arg in argv
        cmd = string(cmd, " ", arg)
    end
    docommand(cmd, pipeline)
end

"""Intersect multiple sets. Multiple sets are provided as an Array."""
function sinter(keys::Array{ASCIIString,1}; pipeline::Bool=false)
    cmd = "SINTER"
    for key in keys
        cmd = string(cmd, " ", key)
    end
    docommand(cmd, pipeline)
end

"""Add multiple sets. Multiple sets are provided as additional arguments."""
function sunion(key::ASCIIString, argv::ASCIIString...; pipeline::Bool=false)
    cmd = string("SUNION ", key)
    for arg in argv
        cmd = string(cmd, " ", arg)
    end
    docommand(cmd, pipeline)
end

"""Add multiple sets. Multiple sets are provided as an Array."""
function sunion(keys::Array{ASCIIString,1}; pipeline::Bool=false)
    cmd = "SUNION"
    for key in keys
        cmd = string(cmd, " ", key)
    end
    docommand(cmd, pipeline)
end

"""Change the selected database for the current connection."""
function selectdb(db::Int)
    do_command(string("SELECT ", db))
end

"""Remove all keys from the current database."""
function flushdb()
    do_command("FLUSHDB")
end

"""Remove all keys from all databases."""
function flushall()
    do_command("FLUSHALL")
end

export start_session, end_session,                                                  # session
    kvset, kvget, incr, incrby, del, exists, getkeys, rdump, rtype,                 # key-value
    hset, hget, hmset, hmget, hgetall, hdel, hexists, hkeys, hvals, hlen, hincrby,  # hash sets
    sadd, smembers, sismember, scard, srem, sdiff, sinter, sunion,                  # sets
    selectdb, flushdb, flushall,                                                    # management
    @pipeline, get_reply,                                                           # pipelining
    do_command, pipeline_command                                                    # generic

end # module
