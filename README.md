# redis_pool

## Synopsis

  minimalistic [redis](http://code.google.com/p/redis/) client for erlang.
  
  Derived from:
  
   - https://github.com/bmizerany/redis-erl/
   - https://github.com/JacobVorreuter/redis_pool/

## Overview

  redis_pool is a redis client implementation that only
  uses redis's [multi bulk command protocol](http://code.google.com/p/redis/wiki/ProtocolSpecification).
  
  It implements connection pools, timeout management, automatic reconnect
  on errors and a very simple sharding mechanism.

## Raw examples

    0> redis_pool:start_link().  % connect to default redis port on localhost
    {ok,<0.33.0>}
    1> redis_pool:expand_pool(10).
    ok
    2> redis:q(["set", "foo", "bar"]).
    {ok,<<"OK">>}
    3> redis:q(["get", "foo"]).
    {ok,<<"bar">>}
    4> redis:q(["sadd", "bar", "a"]).
    {ok,1}
    5> redis:q(["sadd", "bar", "b"]).
    {ok,1}
    6> redis:q(["sadd", "bar", "c"]).
    {ok,1}
    7> redis:q(["lrange", "0", "-1"]).
    {error,<<"ERR wrong number of arguments for 'lrange' command">>}
    7> redis:q(["lrange", "bar", "0", "-1"]).
    {error,<<"ERR Operation against a key holding the wrong kind of value">>}
    8> redis:q(["smembers", "bar"]).
    [{ok,<<"c">>},{ok,<<"a">>},{ok,<<"b">>}]
    9> redis:q(["incr", "counter"]).
    {ok,1}

## Multiple Pools

    1> redis_pool:start_link(one).
    {ok,<0.33.0>}
    2> redis_pool:start_link(two).
    {ok,<0.36.0>}
    3> redis_pool:start_link(three).
    {ok,<0.39.0>}
    4> redis_pool:start_link(four). 
    {ok,<0.42.0>}
    5> redis_pool:expand(one, 10).
    ok
    6> redis_pool:expand(two, 10).
    ok
    7> redis_pool:expand(three, 10).
    ok
    8> redis_pool:expand(four, 10). 
    ok
    9> redis_shard:start_link(shard, [one, two, three, four]).
    {ok,<0.91.0>}
    10> redis:q(redis_shard:pool(shard, "foo"), ["set", "foo", "bar"]).
    {ok, <<"OK">>}


## Breakdance/Breakdown

    redis_pool:start_link() -> ok | {error, Reason}
    redis_pool:start_link(Name) -> ok | {error, Reason}
    redis_pool:start_link(Name, Opts) -> ok | {error, Reason}
    redis_pool:start_link(Name, Opts, MaxRestarts, Interval) -> ok | {error, Reason}
    
      Types:
        
        Name = atom()
        MaxRestarts = Interval = number()
        Options = [Opt]
        Opt = {atom(), Value}
        Value = term()

      Connects to redis server

      The available options are:

      {ip, Ip}

        If the host has several network interfaces, this option
        specifies which one to use.  Default is "127.0.0.1".

      {port, Port}

        Specify which local port number to use.  Default is 6379.

      {pass, Pass}

        Specify to password to auth with upon a successful connect.
        Default is <<>>.

      {db, DbIndex}

        Sepcify the db to use.  Default is 0.

    Name represents the name of the pool you are creating, by default
    it's redis_pool.
    
    MaxRestarts and Interval stop the restart cycle when the
    connections in the pool die too often, where often is defined as
    MaxRestarts in Interval.

    redis:q(Parts) -> {ok, binary()} | {ok, int()} | {error, binary()}
    redis:q(Name, Parts) -> {ok, binary()} | {ok, int()} | {error, binary()}
    redis:q(Name, Parts, Timeout) -> {ok, binary()} | {ok, int()} | {error, binary()}

      Types

        Parts = [Part]

          The sections, in order, of the command to be executed

        Part = binary() | list()

          A section of a redis command

      Tell redis to execute a command.
      
        Name = atom()
        
          Execute a command in a specific pool of connections
        
        Timeout = number()
        
          Specify a timeout in ms after which the call can be considered
          failed and the connection can be recycled.

## Contribute

I'm very open to patches!  Help is greatly appreciated.

- Fork this repo
- Add an issue to this repos issues with a link to you commit/compare-view
- I'll get to it as soon as possible

## LICENSE
Copyright (c) 2010 Blake Mizerany
Copyright (c) 2010 Jacob Vorreuter <jacob.vorreuter@gmail.com>
Copyright (c) 2010 Valentino Volonghi <valentino@adroll.com>

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.