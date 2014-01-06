-module(chronos_daemon).
-include_lib("couch/include/couch_db.hrl").
-behaviour(gen_server).

-export([start_link/0]).

%gen_server exports
-export([init/1, terminate/2, code_change/3]).
-export([handle_call/3, handle_cast/2, handle_info/2]).

examine_period()->
     list_to_integer(couch_config:get("couchdb_scheduler", "examine","60000")).
     
start_link() ->
    ?LOG_DEBUG("chronos_daemon: started..", []),
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    StartExamineTimer = erlang:send_after(1, self(), examine),
    {ok, StartExamineTimer}.

handle_info(examine,ExamineTimer)->
  erlang:cancel_timer(ExamineTimer),
  ?LOG_DEBUG("Just in time ", []),
  %TODO Open every doc in schedules db and... that may takes more than a examine_period() on large db...
  %but no problem because examine restarted after...
   
  %Get all tasks with schedule_time on past and execute them
  %...Make it configurable if actual execute or delete past tasks
   
  %schedule (erlang:send_after) all tasks that have a schedule_time at the next examine_period()
   
  %Restart examine timer
  ExamineAtTimer = erlang:send_after(examine_period(), self(), examine),
  {noreply, ExamineAtTimer};
handle_info(_Msg, Server) ->
    {noreply, Server}.

%unused gen_server staff
terminate(_Reason, _Srv) ->
    ok.

handle_call(_Req, _From, State) ->
    {noreply, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
