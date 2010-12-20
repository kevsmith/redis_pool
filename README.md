# redis_pool

## Synopsis

minimalistic [redis](http://code.google.com/p/redis/) client for erlang.  

Derived from:  

* <https://github.com/bmizerany/redis-erl/>  

Active forks:  

* <https://github.com/dialtone/redis_pool>  

## Overview

  redis_pool is a redis client implementation that only
  uses redis's [multi bulk command protocol](http://code.google.com/p/redis/wiki/ProtocolSpecification).
  
  It implements connection pools, timeout management, automatic reconnect
  on errors and a very simple sharding mechanism.

## Raw examples

    0> redis_pool:start_link().  % connect to default redis port on localhost
    {ok,<0.33.0>}
    1> redis_pool:expand(10).
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

## Multiple Pools with Manager

    1> redis_sup:start_link().
    {ok,<0.33.0>}
    2> redis_shard:start_link(main, []).
    {ok,<0.35.0>}
    3> redis_manager:start_link(main, [{one, [10]}, {two, [10]}, {three, [10]}, {four, [10]}]).
    {ok,<0.37.0>}
    4> redis:q(redis_shard:pool(main, "foo"), ["set", "foo", "bar"]).
    {ok,<<"OK">>}

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

    redis_pool:expand(NewSize) -> ok
    redis_pool:expand(Name, NewSize) -> ok

      Types:
      
        NewSize = number()
        
          Set the connection pool to the given size.
        
        Name = atom()

          Send the call to a specific pool. By default redis_pool.

    redis_pool:pool_size() -> number()
    redis_pool:pool_size(Name) -> number()
    
      Types
      
        Name = atom()
      
      Returns the current number of live connections in the pool.

    redis_pool:pid() -> pid() | {error, term()}
    redis_pool:pid(Name) -> pid() | {error, term()}
    
      Types
      
        Name = atom()
    
      Return a connection from the specified pool or from the default one.
    
    redis_pool:cycle(NewOpts) -> ok
    redis_pool:cycle(Name, NewOpts) -> ok
    
      Types
      
        NewOpts = [NewOpt]
        NewOpt = {atom(), Value}
        Value = term()
        Name = atom()
    
      Recreate every connection in the pool using the provided NewOpts.
      NewOpts follows the same rules as in redis_pool:start_link/4.
      
      Name specifies the name of the connection pool or redis_pool if not
      provided.
    
    redis_pool:info() -> term()
    redis_pool:info(Name) -> term()
    
      Types
      
        Name = atom()

      Returns the current state of the connection pool.
    
    redis_shard:start_link(Servers) -> ok | {error, Reason}
    redis_shard:start_link(Name, Servers) -> ok | {error, Reason}
    
      Types
      
        Servers = [Server]
        Server = term()
        Name = atom()

        Starts a shard manager that splits evenly an md5 interval
        across the given terms in order.
        
        The suggested way of using this is by having each Server be the
        name of a connection pool. But you can also store additional
        information. You'll however need to extract the label to the
        connection pool in order to access it.
    
    redis_shard:pool(Key) -> atom() | {error, Reason}
    redis_shard:pool(Name, Key) -> atom() | {error, Reason}
    
      Types
      
        Key = number() | list()
        Name = atom()
        
        Returns from the given shard the label that contains the
        specified key or index.
    
    redis_shard:update_shards(Servers) -> ok
    redis_shard:update_shards(Name, Servers) -> ok
    
      Types
      
        Servers = [Server]
        Server = term()
        Name = atom()
    
      Updates the initial configuration and redistributes the shards to
      new servers. No consistency checks are done at this point.

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

## LICENSE
Copyright (c) 2010 Jacob Vorreuter <jacob.vorreuter@gmail.com>  
Copyright (c) 2010 Blake Mizerany  <blake.mizerany@gmail.com>  
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