%%%-------------------------------------------------------------------
%%% @author Fernando Benavides <fbenavides@novamens.com>
%%% @copyright (C) 2010 Novamens S.A.
%%% @doc Event Dispatcher for server events received by client processes
%%% @end
%%%
%%% This source file is subject to the New BSD License. You should have received
%%% a copy of the New BSD license with this software. If not, it can be
%%% retrieved from: http://www.opensource.org/licenses/bsd-license.php
%%%-------------------------------------------------------------------
-module(erfb_client_event_dispatcher).
-author('Fernando Benavides <fbenavides@novamens.com>').

-export([start_link/0]).
-export([subscribe/2, subscribe_link/2, unsubscribe/2, subscriptions/0]).
-export([notify/1]).

-export([start_link_unregistered/0]).
-export([subscribe/3, subscribe_link/3, unsubscribe/3, subscriptions/1]).
-export([notify/2]).

-include("erfblog.hrl").
%% @headerfile "erfb.hrl"
-include("erfb.hrl").

%% @type event_handler() = atom() | {atom(), Id :: term()}.  A module to handler events.
-type(event_handler() :: Module :: atom() | {Module :: atom(), Id :: term()}).

%% ====================================================================
%% External functions
%% ====================================================================

%% ====================================================================
%% ?MODULE dispatcher
%% ====================================================================
%% @spec start_link() -> {ok, pid()}
%% @doc  Starts a new event dispatcher
-spec start_link() -> {ok, pid()}.
start_link() ->
    gen_event:start_link({local, ?MODULE}).

%% @spec subscribe_link(event_handler(), term()) -> ok | {'EXIT', term()} | term()
%% @doc  Subscribes and links a handler to the event dispatcher
%% @see  gen_event:add_sup_handler/3
-spec subscribe_link(event_handler(), term()) -> ok | {'EXIT', term()} | term(). 
subscribe_link(EventHandler, InitArgs) ->
    gen_event:add_sup_handler(?MODULE, EventHandler, InitArgs).

%% @spec subscribe(event_handler(), term()) -> ok | {'EXIT', term()} | term()
%% @doc  Subscribes a handler to the event dispatcher
%% @see  gen_event:add_handler/3
-spec subscribe(event_handler(), term()) -> ok | {'EXIT', term()} | term(). 
subscribe(EventHandler, InitArgs) ->
    gen_event:add_handler(?MODULE, EventHandler, InitArgs).

%% @spec unsubscribe(event_handler(), term()) -> term() | {error, module_not_found} | {'EXIT', term()}
%% @doc  Unsubscribes a handler from the event dispatcher
%% @see  gen_event:delete_handler/3
-spec unsubscribe(event_handler(), term()) -> term() | {error, module_not_found} | {'EXIT', term()}.
unsubscribe(EventHandler, Args) ->
    gen_event:delete_handler(?MODULE, EventHandler, Args).

%% @spec subscriptions() -> [event_handler()]
%% @doc  Returns the list of subscriptions
%% @see  gen_event:which_handlers/1
-spec subscriptions() -> [event_handler()].
subscriptions() ->
    gen_event:which_handlers(?MODULE).

%% @spec notify(#server_connected{} | #server_disconnected{}) -> ok
%% @doc  Sends an event to the subscribed handlers
%% @see  gen_event:notify/2
-spec notify(#server_connected{} | #server_disconnected{}) -> ok.
notify(Event) ->
    ?DEBUG("Notifying ~p~n", [element(1, Event)]),
    gen_event:notify(?MODULE, Event).


%% ====================================================================
%% Unregistered dispatcher
%% ====================================================================
%% @spec start_link_unregistered() -> {ok, pid()}
%% @doc  Starts a new event dispatcher for a particular session (i.e. not registered)
-spec start_link_unregistered() -> {ok, pid()}.
start_link_unregistered() ->
    gen_event:start_link().

%% @spec subscribe_link(pid(), event_handler(), term()) -> ok | {'EXIT', term()} | term()
%% @doc  Subscribes and links a handler to the event dispatcher
%% @see  gen_event:add_sup_handler/3
-spec subscribe_link(pid(), event_handler(), term()) -> ok | {'EXIT', term()} | term(). 
subscribe_link(Dispatcher, EventHandler, InitArgs) ->
    gen_event:add_sup_handler(Dispatcher, EventHandler, InitArgs).

%% @spec subscribe(pid(), event_handler(), term()) -> ok | {'EXIT', term()} | term()
%% @doc  Subscribes a handler to the event dispatcher
%% @see  gen_event:add_handler/3
-spec subscribe(pid(), event_handler(), term()) -> ok | {'EXIT', term()} | term(). 
subscribe(Dispatcher, EventHandler, InitArgs) ->
    gen_event:add_handler(Dispatcher, EventHandler, InitArgs).

%% @spec unsubscribe(pid(), event_handler(), term()) -> term() | {error, module_not_found} | {'EXIT', term()}
%% @doc  Unsubscribes a handler from the event dispatcher
%% @see  gen_event:delete_handler/3
-spec unsubscribe(pid(), event_handler(), term()) -> term() | {error, module_not_found} | {'EXIT', term()}.
unsubscribe(Dispatcher, EventHandler, Args) ->
    gen_event:delete_handler(Dispatcher, EventHandler, Args).

%% @spec subscriptions(pid()) -> [event_handler()]
%% @doc  Returns the list of subscriptions
%% @see  gen_event:which_handlers/1
-spec subscriptions(pid()) -> [event_handler()].
subscriptions(Dispatcher) ->
    gen_event:which_handlers(Dispatcher).

%% @spec notify(pid(), server_event()) -> ok
%% @doc  Sends an event to the subscribed handlers
%% @see  gen_event:notify/2
-spec notify(pid(), server_event()) -> ok.
notify(Dispatcher, Event) ->
    ?DEBUG("Notifying ~p through ~p~n", [element(1, Event), Dispatcher]),
    gen_event:notify(Dispatcher, Event).