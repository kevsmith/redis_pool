-module(redis_sup).
-behaviour(supervisor).

%% Supervisor callbacks
-export([add_pool/1, add_pool/2, add_pool/3, add_pool/5, remove_pool/1]).
-export([init/1, start_link/0]).

cycle_if_needed(_Name, Opts, Opts) ->
    ok;
cycle_if_needed(Name, _Opts, NewOpts) ->
    redis_pool:cycle(Name, NewOpts).

add_pool(Size) ->
    add_pool(redis_pool, [], 600, 60000, Size).
add_pool(Name, Size) ->
    add_pool(Name, [], 600, 60000, Size).
add_pool(Name, Opts, Size) ->
    add_pool(Name, Opts, 600, 60000, Size).
add_pool(Name, Opts, MaxRestarts, Interval, Size) ->
    case redis_pool:pid(Name) of
        {error, {not_found, Name}} ->
            {ok, _} = supervisor:start_child(?MODULE, [Name, Opts, MaxRestarts, Interval]);
        _ ->
            cycle_if_needed(Name, redis_pool:info(Name, opts), Opts)
    end,
    redis_pool:expand(Name, Size).

remove_pool(Name) ->
    case redis_pool:pid(Name) of
        {error, {not_found, Name}} ->
            ok;
        _ ->
            redis_pool:stop(Name)
    end.

start_link() ->
    supervisor:start_link({local, ?MODULE}, redis_sup, []).

init([]) ->
    Pool = {undefined, {redis_pool, start_link, []},
                transient, 10000, worker, [redis_pool]},
    
    {ok, {{simple_one_for_one, 100000, 1},
        [Pool]
      }}.
