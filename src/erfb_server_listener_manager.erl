%%%-------------------------------------------------------------------
%%% @author Fernando Benavides <fbenavides@novamens.com>
%%% @copyright (C) 2010 Novamens S.A.
%%% @doc Supervisor for Server Listener Processes
%%% @end
%%%
%%% This source file is subject to the New BSD License. You should have received
%%% a copy of the New BSD license with this software. If not, it can be
%%% retrieved from: http://www.opensource.org/licenses/bsd-license.php
%%%-------------------------------------------------------------------
-module(erfb_server_listener_manager).
-author('Fernando Benavides <fbenavides@novamens.com>').

-behaviour(supervisor).

-export([start_link/0, start_listener/5, init/1, prep_stop/1]).

-include("erfblog.hrl").
%% @headerfile "erfb.hrl"
-include("erfb.hrl").

%% ====================================================================
%% External functions
%% ====================================================================
%% @spec start_link() -> {ok, pid()}
%% @doc  Starts the supervisor process
-spec start_link() -> {ok, pid()}.
start_link() -> 
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% @spec start_listener(#session{}, [{integer(), atom()}], ip(), integer(), integer()) -> {ok, pid() | undefined} | {error, term()}
%% @doc  Starts a new listener process
-spec start_listener(#session{}, [{integer(), atom()}], ip(), integer(), integer()) -> {ok, pid() | undefined} | {error, term()}.
start_listener(Session, Encodings, Ip, Port, Backlog) ->
    supervisor:start_child(?MODULE, [Session, Encodings, Ip, Port, Backlog]).

%% ====================================================================
%% Server functions
%% ====================================================================
%% @hidden
-spec prep_stop(_) -> [any()].
prep_stop(State) ->
    ?INFO("Preparing to stop~n\tChildren: ~p~n", [supervisor:which_children(?MODULE)]),
    [Module:prep_stop(Pid, State) ||
       {_, Pid, _, [Module]} <- supervisor:which_children(?MODULE),
       lists:member({prep_stop, 2}, Module:module_info(exports))].

%% @hidden
-spec init([]) -> {ok, {{simple_one_for_one, 100, 1}, [{undefined, {erfb_server_listener, start_link, []}, temporary, 5000, worker, [erfb_server_listener]}]}}.
init([]) ->
    {ok,
        {_SupFlags = {simple_one_for_one, 100, 1},
            [
              % TCP Client
              {   undefined,                                % Id       = internal id
                  {erfb_server_listener, start_link, []},   % StartFun = {M, F, A}
                  temporary,                                % Restart  = permanent | transient | temporary
                  5000,                                     % Shutdown = brutal_kill | int() >= 0 | infinity
                  worker,                                   % Type     = worker | supervisor
                  [erfb_server_listener]                    % Modules  = [Module] | dynamic
              }
            ]
        }
    }.