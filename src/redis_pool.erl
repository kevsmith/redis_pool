-module(redis_pool).
-behaviour(gen_server).

%% gen_server callbacks
-export([start_link/1, init/1, handle_call/3, handle_cast/2, 
	     handle_info/2, terminate/2, code_change/3]).

-export([pid/0, expand_pool/1, cycle_pool/1]).

-record(state, {opts=[], key='$end_of_table'}).

%% API functions
start_link(Opts) ->
	gen_server:start_link({local, ?MODULE}, ?MODULE, Opts, []).

pid() ->
    gen_server:call(?MODULE, pid).

expand_pool(NewSize) when is_integer(NewSize) ->
    case NewSize - ets:info(?MODULE, size) of
        Additions when Additions > 0 ->
            gen_server:cast(?MODULE, {add, Additions});
        _ ->
            ok
    end.

cycle_pool(NewOpts) ->
    gen_server:cast(?MODULE, {update_opts, NewOpts}),
    [gen_server:cast(Pid, {reconnect, NewOpts}) || {Pid} <- ets:tab2list(?MODULE)].

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
init(Opts) ->
    ets:new(?MODULE, [set, named_table, protected]),
    PoolSize = proplists:get_value(pool_size, Opts, 1),
    [start_client(Opts) || _ <- lists:seq(1, PoolSize)],
	{ok, #state{opts=Opts}}.

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
handle_call(pid, _From, #state{key='$end_of_table'}=State) ->
    case ets:first(?MODULE) of
        '$end_of_table' ->
            {reply, undefined, State#state{key='$end_of_table'}};
        Pid ->
            {reply, Pid, State#state{key=Pid}}
    end;

handle_call(pid, _From, #state{key=Prev}=State) ->
    case ets:next(?MODULE, Prev) of
        '$end_of_table' ->
            case ets:first(?MODULE) of
                '$end_of_table' ->
                    {reply, undefined, State#state{key='$end_of_table'}};
                Pid ->
                    {reply, Pid, State#state{key=Pid}}
            end;
        Pid ->
            {reply, Pid, State#state{key=Pid}}
    end;
    
handle_call(_Msg, _From, State) ->
    {reply, {error, invalid_call}, State}.

%%--------------------------------------------------------------------
%% Function: handle_cast(Msg, State) -> {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, State}
%% Description: Handling cast messages
%% @hidden
%%--------------------------------------------------------------------
handle_cast({add, Additions}, State) ->
    [start_client(State#state.opts) || _ <- lists:seq(1, Additions)],
    {noreply, State};

handle_cast({update_opts, NewOpts}, State) ->
    {noreply, State#state{opts=NewOpts}};

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
%%% Internal functions
%%--------------------------------------------------------------------
start_client(Opts) ->
    {ok, Pid} = gen_server:start_link(redis, Opts, []),
    ets:insert(?MODULE, {Pid}).