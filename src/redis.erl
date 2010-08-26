-module(redis).
-behaviour(gen_server).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, 
         handle_info/2, terminate/2, code_change/3]).

-export([q/1, keys/0, keys/1, set/2, get/1]).

-define(NL, <<"\r\n">>).

-record(state, {
    ip = "127.0.0.1",
    port = 6379,
    db = 0,
    pass,
    socket
}).

%% API functions
q(Parts) ->
    case redis_pool:pid() of
        Pid when is_pid(Pid) ->
            q(Pid, Parts, 1);
        Error ->
            Error
    end.

q(Pid, Parts, Retries) ->
    case gen_server:call(Pid, {q, Parts}) of
        {error, closed} ->
            case Retries > 0 of
                true ->
                    gen_server:call(Pid, reconnect),
                    q(Pid, Parts, Retries-1);
                false ->
                    {error, closed}
            end;
        Result ->
            Result
    end.

%% Generic Sugar
keys() -> keys(<<"*">>).

keys(Pat) when is_binary(Pat) ->
    [Data || {ok, Data} <- q([<<"KEYS">>, Pat])].

set(Key, Value) when is_binary(Key), is_binary(Value) ->
    case q([<<"SET">>, Key, Value]) of
        {ok, Result} -> Result;
        Other -> Other
    end.

get(Key) when is_binary(Key) ->
    case q([<<"GET">>, Key]) of
        {ok, Result} -> Result;
        Other -> Other
    end.

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
init(Opts) ->
    State = init_state(Opts),
    case connect(State#state.ip, State#state.port) of
        {ok, Socket} ->
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
handle_call({q, Parts}, _From, State) ->
    Result = do_q(Parts, State),
    {reply, Result, State};

handle_call({reconnect, NewOpts}, _From, State) ->
    State1 = init_state(NewOpts),
    case connect(State1#state.ip, State1#state.port) of
        {ok, Socket} ->
            {reply, ok, State1#state{socket=Socket}};
        Error ->
            {reply, Error, State}
    end;

handle_call(reconnect, _From, State) ->
    case connect(State#state.ip, State#state.port) of
        {ok, Socket} ->
            {reply, ok, State#state{socket=Socket}};
        Error ->
            {reply, Error, State}
    end.

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
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% Function: terminate(Reason, State) -> void()
%% Description: This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any necessary
%% cleaning up. When it returns, the gen_server terminates with Reason.
%% The return value is ignored.
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
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
init_state(Opts) ->
    State0 =
        case os:getenv("REDIS_URL") of
            false -> #state{};
            URL ->
                case redis_uri:parse(URL) of
                    {redis, _UserInfo, Host, Port, Path, _Query} ->
                        Pass = 
                            case Path of
                                "/" -> undefined;
                                "/" ++ Val -> Val
                            end,
                        #state{ip = Host, port = Port, pass = Pass};
                    _ -> ok
                end
        end,
    parse_options(Opts, State0).

do_q(Parts, #state{socket=Socket}=State) ->
    case do_auth(Socket, State#state.pass) of
        {ok, _Msg} ->
            send_recv(Socket, build_request(Parts));
        Error ->
            Error
    end.
    
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

connect(Ip, Port) ->
    gen_tcp:connect(Ip, Port, [binary, {active, false}, {keepalive, true}]).

do_auth(Socket, Pass) when is_binary(Pass), size(Pass) > 0 ->
    send_recv(Socket, [<<"AUTH ">>, Pass, ?NL]);

do_auth(_Socket, _Pass) ->
    {ok, "not authenticated"}.

send_recv(Socket, Packet) ->
    case gen_tcp:send(Socket, Packet) of
        ok ->
            read_resp(Socket);
        Error ->
            Error
    end.

read_resp(Socket) ->
    inet:setopts(Socket, [{packet, line}]),
    case gen_tcp:recv(Socket, 0) of
        {ok, Line} ->
            case Line of
                <<"*", Rest/binary>> ->
                    Count = list_to_integer(binary_to_list(strip(Rest))),
                    read_multi_bulk(Socket, Count, []);
                <<"+", Rest/binary>> ->
                    {ok, strip(Rest)};
                <<"-", Rest/binary>> ->
                    {error, strip(Rest)};
                <<":", Size/binary>> ->
                    {ok, list_to_integer(binary_to_list(strip(Size)))};
                <<"$", Size/binary>> ->
                    Size1 = list_to_integer(binary_to_list(strip(Size))),
                    read_body(Socket, Size1);
                <<"\r\n">> ->
                    read_resp(Socket);
                Uknown ->
                    {error, {unknown, Uknown}}
            end;
        Error ->
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

read_multi_bulk(_Data, 0, Acc) ->
    lists:reverse(Acc);
read_multi_bulk(Socket, Count, Acc) ->
    Acc1 = [read_resp(Socket) | Acc],
    read_multi_bulk(Socket, Count-1, Acc1).

build_request(Args) when is_list(Args) ->
    Count = length(Args),
    Args1 = [begin
        [<<"$">>, integer_to_list(size(Arg)), ?NL, Arg, ?NL]
     end || Arg <- Args],
    ["*", integer_to_list(Count), ?NL, Args1, ?NL].
