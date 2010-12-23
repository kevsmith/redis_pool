%% Copyright (c) 2010 Jacob Vorreuter <jacob.vorreuter@gmail.com>
%% 
%% Permission is hereby granted, free of charge, to any person
%% obtaining a copy of this software and associated documentation
%% files (the "Software"), to deal in the Software without
%% restriction, including without limitation the rights to use,
%% copy, modify, merge, publish, distribute, sublicense, and/or sell
%% copies of the Software, and to permit persons to whom the
%% Software is furnished to do so, subject to the following
%% conditions:
%% 
%% The above copyright notice and this permission notice shall be
%% included in all copies or substantial portions of the Software.
%% 
%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
%% EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
%% OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
%% NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
%% HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
%% WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
%% FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
%% OTHER DEALINGS IN THE SOFTWARE.
-module(redis_pool).
-behaviour(gen_server).

%% gen_server callbacks
-export([start_link/0, start_link/1, start_link/2, init/1, handle_call/3,
	     handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-export([pid/0, pid/1, add_pool/1, add_pool/2, add_pool/3, remove_pool/1, register/2,
         expand/1, expand/2, expand/3, cycle/1, cycle/2, cycle/3,
         info/0, info/1, pool_size/0, pool_size/1, info/2, stop/0, stop/1]).

-record(state, {opts=[], key='$end_of_table', tid}).

-define(TIMEOUT, 8000).

%% API functions
start_link() ->
    start_link(?MODULE, []).

start_link(Name) when is_atom(Name) ->
    start_link(Name, []);

start_link(Opts) when is_list(Opts) ->
    gen_server:start_link(?MODULE, [Opts], []).

start_link(Name, Opts) when is_atom(Name), is_list(Opts) ->
    gen_server:start_link({local, Name}, ?MODULE, [Opts], []).

register(Name, Pid) ->
    gen_server:cast(Name, {register, Pid}).

cycle_if_needed(_Name, Opts, Opts) ->
    ok;
cycle_if_needed(Name, _Opts, NewOpts) ->
    cycle(Name, NewOpts).

add_pool(Size) ->
    add_pool(redis_pool, [], Size).
add_pool(Name, Size) ->
    add_pool(Name, [], Size).
add_pool(Name, Opts, Size) ->
    case pid(Name) of
        {error, {not_found, Name}} ->
            {ok, _} = redis_pool_sup:start_child(Name, Opts);
        _ ->
            cycle_if_needed(Name, info(Name, opts), Opts)
    end,
    expand(Name, Size, 30 * 1000).

remove_pool(Name) ->
    case pid(Name) of
        {error, {not_found, Name}} ->
            ok;
        _ ->
            stop(Name)
    end.

pid() ->
    pid(?MODULE).

pid(Pool) when is_atom(Pool); is_pid(Pool) ->
    case catch gen_server:call(Pool, pid) of
        {'EXIT', {noproc, _}} ->
            {error, {not_found, Pool}};
        R ->
            R
    end;

pid(Pool) ->
    {error, {invalid_name, Pool}}.
    
pool_size() ->
    pool_size(?MODULE).

pool_size(Name) ->
    gen_server:call(Name, pool_size).

expand(NewSize) ->
    expand(?MODULE, NewSize).

expand(Name, NewSize) ->
    expand(Name, NewSize, ?TIMEOUT).

expand(Name, NewSize, Timeout) when is_integer(NewSize), is_integer(Timeout) ->
    gen_server:call(Name, {expand, NewSize}, Timeout).

cycle(NewOpts) ->
    cycle(?MODULE, NewOpts).

cycle(Name, NewOpts) ->
    cycle(Name, NewOpts, ?TIMEOUT).

cycle(Name, NewOpts, Timeout) when is_list(NewOpts), is_integer(Timeout) ->
    gen_server:call(Name, {cycle, NewOpts}, Timeout).

info() ->
    info(?MODULE).

info(Name) ->
    gen_server:call(Name, info).

info(Name, opts) ->
    R = info(Name),
    R#state.opts;
info(Name, tid) ->
    R = info(Name),
    R#state.tid.

stop() ->
    stop(?MODULE).
stop(Name) ->
    gen_server:call(Name, stop).

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
init([Opts]) ->
    Tid = ets:new(undefined, [set, protected]),
    {ok, #state{tid=Tid, opts=Opts}}.

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
handle_call(pid, _From, #state{key='$end_of_table', tid=Tid}=State) ->
    case ets:first(Tid) of
        '$end_of_table' ->
            {reply, undefined, State#state{key='$end_of_table'}};
        Pid ->
            {reply, Pid, State#state{key=Pid}}
    end;

handle_call(pid, _From, #state{key=Prev, tid=Tid}=State) ->
    case ets:next(Tid, Prev) of
        '$end_of_table' ->
            case ets:first(Tid) of
                '$end_of_table' ->
                    {reply, undefined, State#state{key='$end_of_table'}};
                Pid ->
                    {reply, Pid, State#state{key=Pid}}
            end;
        Pid ->
            {reply, Pid, State#state{key=Pid}}
    end;

handle_call({expand, NewSize}, _From, State) ->
    case NewSize - ets:info(State#state.tid, size) of
        Additions when Additions > 0 ->
            [redis_pid_sup:start_child(self(), State#state.opts) || _ <- lists:seq(1, Additions)],
            ok;
        _ ->
            ok
    end,
    {reply, ok, State};

handle_call({cycle, NewOpts}, _From, State) ->
    [gen_server:call(Pid, {reconnect, NewOpts}) || {Pid, _} <- ets:tab2list(State#state.tid)],
    {reply, ok, State#state{opts=NewOpts}};

handle_call(info, _From, State) ->
    {reply, State, State};

handle_call(pool_size, _From, State) ->
    {reply, ets:info(State#state.tid, size), State};

handle_call(stop, _From, State) ->
    {stop, normal, ok, State};

handle_call(_Msg, _From, State) ->
    {reply, {error, invalid_call}, State}.

%%--------------------------------------------------------------------
%% Function: handle_cast(Msg, State) -> {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, State}
%% Description: Handling cast messages
%% @hidden
%%--------------------------------------------------------------------
handle_cast({register, Pid}, #state{tid=Tid}=State) ->
    erlang:monitor(process, Pid),
    ets:insert(Tid, {Pid, undefined}),
    {noreply, State};

handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% Function: handle_info(Info, State) -> {noreply, State} |
%%                                       {noreply, State, Timeout} |
%%                                       {stop, Reason, State}
%% Description: Handling all non call/cast messages
%% @hidden
%%--------------------------------------------------------------------
handle_info({'DOWN', _MonitorRef, process, Pid, _Info}=Msg, #state{tid=Tid, key=Prev}=State) ->
    case ets:lookup(Tid, Pid) of
        [{Pid, Caller}] when is_pid(Caller) ->
            Caller ! Msg;
        _ ->
            ok
    end,
    ets:delete(Tid, Pid),

    % If I'm removing the previous element in the ets tab I need to reset
    % the state of the last key otherwise I'll get badarg over and over
    case Prev == Pid of
        true ->
            {noreply, State#state{key='$end_of_table'}};
        false ->
            {noreply, State}
    end;

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
terminate(_Reason, State) ->
    [gen_server:cast(Pid, die) || {Pid, _} <- ets:tab2list(State#state.tid)],
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