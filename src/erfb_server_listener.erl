%%%-------------------------------------------------------------------
%%% @author Fernando Benavides <fbenavides@novamens.com>
%%% @copyright (C) 2010 Novamens S.A.
%%% @doc Listener process for RFB servers
%%% @reference See <a href="http://www.trapexit.org/index.php/Building_a_Non-blocking_TCP_server_using_OTP_principles">this article</a> for more information
%%% @end
%%%
%%% This source file is subject to the New BSD License. You should have received
%%% a copy of the New BSD license with this software. If not, it can be
%%% retrieved from: http://www.opensource.org/licenses/bsd-license.php
%%%-------------------------------------------------------------------
-module(erfb_server_listener).
-author('Fernando Benavides <fbenavides@novamens.com>').

-behaviour(gen_server).

%% -------------------------------------------------------------------
%% Exported functions
%% -------------------------------------------------------------------
-export([start_link/5, stop/1, prep_stop/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).
-export([set_pixel_format/2]).

%% -------------------------------------------------------------------
%% Include files
%% -------------------------------------------------------------------
-include("erfblog.hrl").
%% @headerfile "erfb.hrl"
-include("erfb.hrl").

-record(state, {
                session   :: #session{},            % Session description
                encodings :: [{integer(), atom()}], % Supported encodings
                listener  :: port(),                % Listening socket
                acceptor  :: term()                 % Asynchronous acceptor's internal reference
               }).

%% ====================================================================
%% External functions
%% ====================================================================
%% @spec start_link(#session{}, [{integer(), atom()}], ip(), non_neg_integer(), non_neg_integer()) -> {ok, pid()}
%% @doc  Starts a new server listerner
-spec start_link(#session{}, [{integer(), atom()}], ip(), non_neg_integer(), non_neg_integer()) -> {ok, pid()}.
start_link(Session, Encodings, Ip, Port, Backlog) -> 
    ?INFO("Starting RFB Server Listener on ~p for:~n\t~p~n", [Port, Session]),
    gen_server:start_link(?MODULE, {Session, Encodings, Ip, Port, Backlog}, []).

%% @spec stop(pid()) -> ok
%% @doc  Stops a running listener
-spec stop(pid()) -> ok.
stop(Listener) ->
    ?INFO("Stopping RFB Server Listener~n", []),
    gen_server:call(Listener, stop).

%% @spec set_pixel_format(pid(), #pixel_format{}) -> ok
%% @doc  Modifies the informed pixel_format in a running listener
-spec set_pixel_format(pid(), #pixel_format{}) -> ok.
set_pixel_format(Listener, PF) ->
    ?INFO("Setting RFB Server Listener PF: ~p~n", [PF]),
    gen_server:call(Listener, PF).

%% @hidden
-spec prep_stop(pid(), term()) -> ok.
prep_stop(Listener, Reason) ->
    ?INFO("Stopping RFB Server Listener: ~p~n", [Reason]),
    gen_server:call(Listener, stop).

%% ====================================================================
%% Callback functions
%% ====================================================================
%% @hidden
-spec init({#session{}, [{integer(), atom()}], ip(), non_neg_integer(), non_neg_integer()}) -> {ok, #state{}} | {stop, atom()}.
init({Session, Encodings, Ip, Port, Backlog}) ->
    process_flag(trap_exit, true),
    Opts = [binary,
            {backlog, Backlog},
            {ip, Ip},
            {reuseaddr, true},
            {keepalive, true},
            {packet, 0},
            {active, false}],
    case gen_tcp:listen(Port, Opts) of
        {ok, Socket} ->
            %%Create first accepting process
            {ok, Ref} = prim_inet:async_accept(Socket, -1),
            {ok, #state{session  = Session,
                        encodings= Encodings,
                        listener = Socket,
                        acceptor = Ref}};
        {error, Reason} ->
            {stop, Reason}
    end.

%% @hidden
-spec handle_call(any(), any(), #state{}) -> {reply, ok, #state{}} | {stop, normal, ok, #state{}}.
handle_call(PF, _From, State = #state{session = Session})
  when is_record(PF, pixel_format) ->
    {reply, ok, State#state{session = Session#session{pixel_format = PF}}};
handle_call(stop, _From, State) ->
    {stop, normal, ok, State}.

%% @hidden
-spec handle_cast(any(), #state{}) -> {noreply, #state{}}.
handle_cast(_Msg, State) ->
    {noreply, State}.

%% @hidden
-spec handle_info(any(), #state{}) -> {noreply, #state{}}.
handle_info({inet_async, ListSock, Ref, {ok, SrvSocket}},
            #state{session  = Session,
                   encodings= Encodings,
                   listener = ListSock,
                   acceptor = Ref} = State) ->
    try
        case set_sockopt(ListSock, SrvSocket) of
            ok ->
                void;
            {error, Reason} ->
                exit({set_sockopt, Reason})
        end,
        
        %% New server connected - spawn a new process using the simple_one_for_one
        %% supervisor.
        {ok, Pid} = erfb_server_manager:start_server(Session, Encodings),
        gen_tcp:controlling_process(SrvSocket, Pid),
        
        %% Instruct the new FSM that it owns the socket.
        erfb_server_process:set_socket(Pid, SrvSocket),
        
        %% Signal the network driver that we are ready to accept another connection
        NewRef =
            case prim_inet:async_accept(ListSock, -1) of
                {ok, NR} ->
                    NR;
                {error, Err} ->
                    exit({async_accept, inet:format_error(Err)})
            end,
        
        {noreply, State#state{acceptor=NewRef}}
    catch
        exit:Error ->
            ?ERROR("Error in async accept: ~p.\n", [Error]),
            {stop, Error, State}
    end;
handle_info({inet_async, ListSock, Ref, Error},
            #state{listener = ListSock, acceptor = Ref} = State) ->
    ?ERROR("Error in socket acceptor: ~p.\n", [Error]),
    {stop, Error, State};
handle_info(_Info, State) ->
    {noreply, State}.

%% @hidden
-spec terminate(_, #state{}) -> ok.
terminate(Reason, #state{session = #session{server = ServerId,
                                            client = ClientId}}) ->
    ?INFO("RFB listener terminated: ~p~n", [Reason]),
    erfb_server_event_dispatcher:notify(
      #listener_disconnected{server = ServerId,
                             client = ClientId,
                             reason = Reason}).

%% @hidden
-spec code_change(any(), any(), any()) -> {ok, any()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% ====================================================================
%% Internal functions
%% ====================================================================
%% @doc Taken from prim_inet.  We are merely copying some socket options from the
%%      listening socket to the new server socket.
-spec set_sockopt(port(), port()) -> ok | {error, Reason :: term()}.
set_sockopt(ListSock, SrvSocket) ->
    true = inet_db:register_socket(SrvSocket, inet_tcp),
    case prim_inet:getopts(ListSock, [active, nodelay, keepalive, delay_send, priority, tos]) of
        {ok, Opts} ->
            case prim_inet:setopts(SrvSocket, Opts) of
                ok ->
                    ok;
                Error ->
                    gen_tcp:close(SrvSocket),
                    Error
            end;
        Error ->
            gen_tcp:close(SrvSocket),
            Error
    end.