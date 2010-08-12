-module(redis_app).
-behaviour(application).

%% Application callbacks
-export([start/2, stop/1, init/1]).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

stop(_State) ->
    ok.

init([]) ->
    {ok, {{one_for_one, 5, 10}, [
        {redis, {redis, start_link, [[]]}, permanent, 2000, worker, [redis]}
    ]}}.