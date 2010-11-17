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
-export([start_link/0, start_link/1, init/1, handle_call/3,
	     handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-export([pid/0, pid/1, expand_pool/1, expand_pool/2,
         cycle_pool/1, cycle_pool/2, info/0, info/1]).

-record(state, {opts=[], key='$end_of_table', restarts=0, tid}).

-define(MAX_RESTARTS, 600).

%% API functions
start_link() ->
    start_link(?MODULE).

start_link(Name) when is_atom(Name) ->
	gen_server:start_link({local, Name}, ?MODULE, [], []).

pid() ->
    pid(?MODULE).

pid(Name) when is_atom(Name) ->
    gen_server:call(Name, pid).

expand_pool(NewSize) ->
    expand_pool(?MODULE, NewSize).

expand_pool(Name, NewSize) when is_atom(Name), is_integer(NewSize) ->
    gen_server:cast(Name, {expand, NewSize}).

cycle_pool(NewOpts) ->
    cycle_pool(?MODULE, NewOpts).

cycle_pool(Name, NewOpts) when is_atom(Name), is_list(NewOpts) ->
    gen_server:cast(Name, {cycle_pool, NewOpts}).

info() ->
    info(?MODULE).

info(Name) when is_atom(Name) ->
    gen_server:call(Name, info).

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
init([]) ->
    Tid = ets:new(undefined, [set, protected]),
    Self = self(),
    spawn_link(fun() -> clear_restarts(Self) end),
	{ok, #state{tid=Tid}}.

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

handle_call(info, _From, State) ->
    {reply, State, State};

handle_call(_Msg, _From, State) ->
    {reply, {error, invalid_call}, State}.

%%--------------------------------------------------------------------
%% Function: handle_cast(Msg, State) -> {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, State}
%% Description: Handling cast messages
%% @hidden
%%--------------------------------------------------------------------
handle_cast({expand, NewSize}, State) ->
    case NewSize - ets:info(State#state.tid, size) of
        Additions when Additions > 0 ->
            [start_client(State#state.tid, State#state.opts) || _ <- lists:seq(1, Additions)];
        _ ->
            ok
    end,
    {noreply, State};

handle_cast({cycle_pool, NewOpts}, State) ->
    [gen_server:cast(Pid, {reconnect, NewOpts}) || {Pid, _} <- ets:tab2list(State#state.tid)],
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
handle_info({'DOWN', _MonitorRef, process, Pid, _Info}, #state{restarts=Restarts, tid=Tid}=State) ->
    ets:delete(Tid, Pid),
    Restarts < ?MAX_RESTARTS andalso start_client(Tid, State#state.opts),
    {noreply, State#state{restarts=Restarts+1}};

handle_info(clear_restarts, State) ->
    {noreply, State#state{restarts=0}};

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
start_client(Tid, Opts) ->
    {ok, Pid} = gen_server:start(redis, Opts, []),
    MonitorRef = erlang:monitor(process, Pid),
    ets:insert(Tid, {Pid, MonitorRef}).

clear_restarts(Pid) ->
    timer:sleep(1000 * 60),
    Pid ! clear_restarts,
    clear_restarts(Pid).
