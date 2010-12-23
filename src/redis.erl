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
-module(redis).
-behaviour(gen_server).

%% gen_server callbacks
-export([start_link/2, init/1, handle_call/3, handle_cast/2, 
         handle_info/2, terminate/2, code_change/3]).

-export([build_request/1, connect/3, send_recv/3, stop/1]).

-export([q/1, q/2, q/3, subscribe/3]).

-define(NL, <<"\r\n">>).

-record(state, {ip = "127.0.0.1", port = 6379, db = 0, pass, socket, key, callback, buffer}).

-define(TIMEOUT, 5000).

%% API functions
start_link(Pool, Opts) ->
    gen_server:start_link(?MODULE, [Pool, Opts], []).

q(Parts) ->
    q(redis_pool, Parts).

q(Name, Parts) ->
    q(Name, Parts, ?TIMEOUT).

q(Name, Parts, Timeout) when is_atom(Name) ->
    case redis_pool:pid(Name) of
        Pid when is_pid(Pid) ->
            q(Pid, Parts, Timeout);
        Error ->
            Error
    end;

q(Pid, Parts, Timeout) when is_pid(Pid) ->
    %% It can happen that a call is in progress while this Pid dies,
    %% In that case catch the exception and return it, the caller will
    %% deal with the unexpected return value. Also it's possible to
    %% trigger timeouts
    case catch gen_server:call(Pid, {q, Parts, Timeout}, Timeout) of
        {error, Reason} when is_binary(Reason) ->
            %% genuine Redis error
            {error, Reason};
        {'EXIT', {timeout, _C}} ->
            {error, timeout};
        Result ->
            Result
    end.

subscribe(Pid, Key, Callback) ->
    gen_server:call(Pid, {subscribe, Key, Callback}).

stop(Pid) ->
    gen_server:call(Pid, stop).

%%====================================================================
%% gen_server callbacks
%%====================================================================

%%--------------------------------------------------------------------
%% Function: init(Args) -> {ok, State} |
%%    {ok, State, Timeout} |
%%    ignore                             |
%%    {stop, Reason}
%% Description: Initiates the server
%%--------------------------------------------------------------------
init([Pool, Opts]) ->
    State = parse_options(Opts, #state{}),
    case connect(State#state.ip, State#state.port, State#state.pass) of
        {ok, Socket} ->
            Pool =/= undefined andalso redis_pool:register(Pool, self()),
            {ok, State#state{socket=Socket}};
        Error ->
            {stop, Error}
    end.

%%--------------------------------------------------------------------
%% Function: %% handle_call(Request, From, State) -> {reply, Reply, State} |
%%    {reply, Reply, State, Timeout} |
%%    {noreply, State} |
%%    {noreply, State, Timeout} |
%%    {stop, Reason, Reply, State} |
%%    {stop, Reason, State}
%% Description: Handling call messages
%%--------------------------------------------------------------------
handle_call({q, Parts, Timeout}, _From, State) ->
    case do_q(Parts, Timeout, State) of
        {redis_error, Error} ->
            {reply, {error, Error}, State};
        {error, timeout} ->
            {reply, {error, timeout}, State};
        {error, Reason} ->
            {stop, Reason, {error, Reason}, State};
        Result ->
            {reply, Result, State}
    end;

handle_call({subscribe, Key, Callback}, _From, #state{socket=Socket}=State) ->
    case do_q([<<"SUBSCRIBE">>, Key], ?TIMEOUT, State) of
        {error, Reason} ->
            {stop, Reason, {error, Reason}, State};
        [{ok, <<"subscribe">>}, {ok, Key}, {ok, _}] ->
            inet:setopts(Socket, [{active, true}]),
            {reply, ok, State#state{key=Key, callback=Callback, buffer=[]}}
    end;

handle_call({reconnect, NewOpts}, _From, State) ->
    State1 = parse_options(NewOpts, #state{}),
    case reconnect(State1#state{socket=State#state.socket}) of
        State2 when is_record(State2, state) ->
            {reply, ok, State2};
        Err ->
            {reply, Err, State}
    end;

handle_call(reconnect, _From, State) ->
    case reconnect(State) of
        State1 when is_record(State1, state) ->
            {reply, ok, State1};
        Err ->
            {reply, Err, State}
    end;

handle_call(stop, _From, State) ->
    {stop, normal, ok, State};

handle_call(_Msg, _From, State) ->
    {reply, unknown_message, State}.

%%--------------------------------------------------------------------
%% Function: handle_cast(Msg, State) -> {noreply, State} |
%%    {noreply, State, Timeout} |
%%    {stop, Reason, State}
%% Description: Handling cast messages
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% Function: handle_info(Info, State) -> {noreply, State} |
%%    {noreply, State, Timeout} |
%%    {stop, Reason, State}
%% Description: Handling all non call/cast messages
%%--------------------------------------------------------------------
handle_info({tcp, _Socket, Packet}, #state{callback=Callback, buffer=[_, BinKey, _, <<"message\r\n">>, _, <<"*3\r\n">>]}=State) ->
    SizeKey = size(BinKey) - 2,
    SizeMsg = size(Packet) - 2,
    <<Key:SizeKey/binary, "\r\n">> = BinKey,
    <<Msg:SizeMsg/binary, "\r\n">> = Packet,
    case Callback of
        {M,F,A} -> apply(M, F, A ++ [{message, Key, Msg}]);
        {Fun, Args} -> apply(Fun, Args ++ [{message, Key, Msg}]);
        Fun -> Fun({message, Key, Msg})
    end,
    {noreply, State#state{buffer=[]}};

handle_info({tcp, _Socket, Packet}, #state{buffer=Buffer}=State) ->
    {noreply, State#state{buffer=[Packet|Buffer]}};

handle_info({tcp_closed, _Socket}, #state{key=Key}=State) ->
    case reconnect(State) of
        State1 when is_record(State1, state) ->
            case do_q([<<"SUBSCRIBE">>, Key], ?TIMEOUT, State1) of
                {error, Reason} ->
                    {stop, {error, Reason}, State};
                [{ok, <<"subscribe">>}, {ok, Key}, {ok, _}] ->
                    inet:setopts(State1#state.socket, [{active, true}]),
                    {noreply, State1#state{buffer=[]}}
            end;
        {error, econnrefused} ->
            erlang:send_after(1000, self(), {tcp_closed, _Socket}),
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
%%--------------------------------------------------------------------
terminate(_Reason, State) ->
    disconnect(State),
    ok.

%%--------------------------------------------------------------------
%% Func: code_change(OldVsn, State, Extra) -> {ok, NewState}
%% Description: Convert process state when code is changed
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%--------------------------------------------------------------------
%% Internal functions
%%--------------------------------------------------------------------
disconnect(#state{socket=Socket}) ->
    catch gen_tcp:close(Socket).

reconnect(State) ->
    case connect(State#state.ip, State#state.port, State#state.pass) of
        {ok, Socket} ->
            disconnect(State),
            State#state{socket=Socket};
        Error ->
            Error
    end.

do_q(Parts, Timeout, State) when is_list(Parts) ->
    send_recv(State, Timeout, build_request(Parts));

do_q(Packet, Timeout, State) when is_binary(Packet) ->
    send_recv(State, Timeout, Packet).
    
parse_options([], State) ->
    State;
parse_options([{ip, Ip} | Rest], State) ->
    parse_options(Rest, State#state{ip = Ip});
parse_options([{port, Port} | Rest], State) ->
    parse_options(Rest, State#state{port = Port});
parse_options([{db, Db} | Rest], State) ->
    parse_options(Rest, State#state{db = Db});
parse_options([{pass, Pass} | Rest], State) ->
    parse_options(Rest, State#state{pass = Pass}).

connect(Ip, Port, Pass) ->
    case gen_tcp:connect(Ip, Port, [binary, {active, false}, {keepalive, true}]) of
        {ok, Sock} when Pass == undefined ->
            {ok, Sock};
        {ok, Sock} ->
            case do_auth(Sock, Pass) of
                {ok, <<"OK">>} -> {ok, Sock};
                Err -> Err
            end;
        Err ->
            Err
    end.

do_auth(Socket, Pass) when is_binary(Pass), size(Pass) > 0 ->
    send_recv(Socket, ?TIMEOUT, [<<"AUTH ">>, Pass, ?NL]);

do_auth(_Socket, _Pass) ->
    {ok, "not authenticated"}.

send_recv(Socket, Timeout, Packet) when is_port(Socket) ->
    case gen_tcp:send(Socket, Packet) of
        ok ->
            read_resp(Socket, Timeout);
        Error ->
            Error
    end;

send_recv(State, Timeout, Packet) when is_record(State, state) ->
    send_recv(State, Timeout, Packet, 2, undefined).

send_recv(_State, _Timeout, _Packet, 0, Err) ->
    Err;

send_recv(State, Timeout, Packet, Retries, _Err) ->
    case gen_tcp:send(State#state.socket, Packet) of
        ok ->
            case read_resp(State#state.socket, Timeout) of
                {error, timeout} ->
                    {error, timeout};
                {error, Err} ->
                    send_recv(reconnect(State), Timeout, Packet, Retries-1, {error, Err});
                Res ->
                    Res
            end;
        Err ->
            send_recv(reconnect(State), Timeout, Packet, Retries-1, Err)
    end.

read_resp(Socket, Timeout) ->
    inet:setopts(Socket, [{packet, line}]),
    case gen_tcp:recv(Socket, 0, Timeout) of
        {ok, Line} ->
            case Line of
                <<"*", Rest/binary>> ->
                    Count = list_to_integer(binary_to_list(strip(Rest))),
                    read_multi_bulk(Socket, Timeout, Count, []);
                <<"+", Rest/binary>> ->
                    {ok, strip(Rest)};
                <<"-", Rest/binary>> ->
                    {redis_error, strip(Rest)};
                <<":", Size/binary>> ->
                    {ok, list_to_integer(binary_to_list(strip(Size)))};
                <<"$", Size/binary>> ->
                    Size1 = list_to_integer(binary_to_list(strip(Size))),
                    read_body(Socket, Size1);
                <<"\r\n">> ->
                    read_resp(Socket, Timeout);
                Uknown ->
                    {error, {unknown, Uknown}}
            end;
        Error ->
            gen_tcp:close(Socket),
            Error
    end.

strip(B) when is_binary(B) ->
    S = size(B) - size(?NL),
    <<B1:S/binary, _/binary>> = B,
    B1.
    
read_body(_Socket, -1) ->
    {ok, undefined};
read_body(_Socket, 0) ->
    {ok, <<>>};
read_body(Socket, Size) ->
    inet:setopts(Socket, [{packet, raw}]),
    gen_tcp:recv(Socket, Size).

read_multi_bulk(_Data, _Timeout, 0, Acc) ->
    lists:reverse(Acc);
read_multi_bulk(Socket, Timeout, Count, Acc) ->
    Acc1 = [read_resp(Socket, Timeout) | Acc],
    read_multi_bulk(Socket, Timeout, Count-1, Acc1).

build_request(Args) when is_list(Args) ->
    Count = length(Args),
    Args1 = [begin
        [<<"$">>, integer_to_list(iolist_size(Arg)), ?NL, Arg, ?NL]
     end || Arg <- Args],
    ["*", integer_to_list(Count), ?NL, Args1, ?NL].

