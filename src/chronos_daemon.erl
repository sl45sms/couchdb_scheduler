-module(chronos_daemon).
-include_lib("couch/include/couch_db.hrl").
-behaviour(gen_server).

-export([start_link/0, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

start_link() ->
    ?LOG_DEBUG("chronos_daemon: starting..", []),
    gen_server:start_link({local, chronos_daemon}, chronos_daemon, [], []).

init([]) ->
    {ok, {}}.

terminate(_Reason, _Srv) ->
    ok.

handle_call(_Req, _From, State) ->
    {noreply, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Msg, Server) ->
    {noreply, Server}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
