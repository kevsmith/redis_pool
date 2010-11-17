-module(redis_sup).
-behaviour(supervisor).

%% Supervisor callbacks
-export([start_link/0, start_link/1, start_link/2, start_link/4]).
-export([init/1]).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

start_link() ->
    start_link([]).
start_link(Opts) ->
    start_link(redis_pool, Opts).
start_link(Name, Opts) ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, [Name, Opts]).
start_link(Name, Opts, MaxRestarts, Interval) ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, [Name, Opts, MaxRestarts, Interval]).


init(Args) ->
    {ok, {{one_for_one, 5, 10}, [
        {redis_pool, {redis_pool, start_link, Args}, permanent, 2000, worker, [redis_pool]}
    ]}}.
