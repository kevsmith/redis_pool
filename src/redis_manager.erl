-module(redis_manager).
-behaviour(gen_server).

%% gen_server callbacks
-export([start_link/2, start_link/3, init/1, handle_call/3,
	     handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-record(state, {shard, config}).

%% API
-export([update_configuration/1, update_configuration/2]).

start_link(Shard, Configuration) ->
    start_link(?MODULE, Shard, Configuration).
start_link(Name, Shard, Configuration) ->
    gen_server:start_link({local, Name}, ?MODULE, [Shard, Configuration], []).

update_configuration(NewConfiguration) ->
    update_configuration(?MODULE, NewConfiguration).
update_configuration(Name, NewConfiguration) ->
    gen_server:call(Name, {update_configuration, NewConfiguration}).

%%====================================================================
%% gen_server callbacks
%%====================================================================
%%--------------------------------------------------------------------
%% Function: init(Args) -> {ok, State} |
%%                         {ok, State, Timeout} |
%%                         ignore               |
%%                         {stop, Reason}
%% Description: Initiates the server
%% @hidden
%%--------------------------------------------------------------------
init([Shard, Configuration]) ->
    setup_pools(Shard, Configuration, sets:new()),
    {ok, #state{shard=Shard, config=Configuration}}.

%%--------------------------------------------------------------------
%% Function: %% handle_call(Request, From, State) -> {reply, Reply, State} |
%%                                      {reply, Reply, State, Timeout} |
%%                                      {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, Reply, State} |
%%                                      {stop, Reason, State}
%% Description: Handling call messages
%% @hidden
%%--------------------------------------------------------------------
handle_call({update_configuration, NewConfiguration}, _From, State) ->
    setup_pools(State#state.shard, NewConfiguration, to_set(dict:from_list(State#state.config))),
    {reply, ok, State#state{config=NewConfiguration}};
handle_call(_Msg, _From, State) ->
    {reply, {error, invalid_call}, State}.

%%--------------------------------------------------------------------
%% Function: handle_cast(Msg, State) -> {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, State}
%% Description: Handling cast messages
%% @hidden
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% Function: handle_info(Info, State) -> {noreply, State} |
%%                                       {noreply, State, Timeout} |
%%                                       {stop, Reason, State}
%% Description: Handling all non call/cast messages
%% @hidden
%%--------------------------------------------------------------------
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% Function: terminate(Reason, State) -> void()
%% Description: This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any necessary
%% cleaning up. When it returns, the gen_server terminates with Reason.
%% The return value is ignored.
%% @hidden
%%--------------------------------------------------------------------
terminate(_Reason, _State) -> 
    ok.

%%--------------------------------------------------------------------
%% Func: code_change(OldVsn, State, Extra) -> {ok, NewState}
%% Description: Convert process state when code is changed
%% @hidden
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%%--------------------------------------------------------------------
%% Internal functions
%%--------------------------------------------------------------------
setup_pools(Shard, NewConnections, CurrentLabels) ->
    NewLabels = add_pools(NewConnections),
    % Needs to happen here to not
    % Remove pools that are still
    % being served as accessible.
    redis_shard:update_shards(Shard, NewLabels),
    remove_pools(sets:to_list(sets:subtract(CurrentLabels, sets:from_list(NewLabels)))).

add_pools(Conns) ->
    add_pools(Conns, []).

add_pools([], Labels) ->
    lists:reverse(Labels);
add_pools([{Label, Options}|Rest], Labels) ->
    erlang:apply(redis_sup, add_pool, [Label|Options]),
    add_pools(Rest, [Label|Labels]).


remove_pools([]) ->
    ok;
remove_pools([Label|Rest]) ->
    redis_sup:remove_pool(Label),
    remove_pools(Rest).


to_set(D) ->
    sets:from_list(dict:fetch_keys(D)).
