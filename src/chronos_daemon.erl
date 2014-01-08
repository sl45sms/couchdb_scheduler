-module(chronos_daemon).
-include_lib("couch/include/couch_db.hrl").
-behaviour(gen_server).

-export([start_link/0,do_earlier_tasks/1,exec_task/1]).

%gen_server exports
-export([init/1, terminate/2, code_change/3]).
-export([handle_call/3, handle_cast/2, handle_info/2]).

-define(SCHEDULES_DB_DOC_RETURNPAST_FUN,<<"
function(doc){ScheduleDate= new Date(doc.schedule_time);MyDate = new Date();if (ScheduleDate<MyDate) emit('PAST '+doc.schedule_time, doc._rev);}
">>).

-define(SCHEDULES_DB_DOC_RETURNFUTURE_FUN,<<"
function(doc){ScheduleDate= new Date(doc.schedule_time);MyDate = new Date();if (ScheduleDate>MyDate) emit(doc.schedule_time+' '+ScheduleDate.toString(), doc._rev);}
">>).

examine_period()->
     list_to_integer(couch_config:get("couchdb_scheduler", "examine","60000")).

ensure_schedules_ddoc_exists(DbName, DDocID) ->
    case couch_db:open_doc(DbName, DDocID, []) of
    {ok, _Doc} ->
        ok;
    _ -> 
        DDoc = couch_doc:from_json_obj({[
        {<<"_id">>,<<"_design/getbydate">>},
        {<<"views">>,
        {[
          {<<"returnpasttasks">>,
            {[{<<"map">>,?SCHEDULES_DB_DOC_RETURNPAST_FUN}]}},
              {<<"returnfuturetasks">>,
                 {[{<<"map">>,?SCHEDULES_DB_DOC_RETURNFUTURE_FUN}]}}
            ]}
        },
       {<<"language">>,<<"javascript">>}
       ]}),
        {ok, _Rev} = couch_db:update_doc(DbName, DDoc, [])
     end.

%may put this funs on another source (schedulel_utils.erl?)
ensure_schedules_db_exists(DbName, Options) ->
    Options1 = [{user_ctx, #user_ctx{roles=[<<"_admin">>]}}, nologifmissing | Options],
    case couch_db:open(DbName, Options1) of
    {ok, Db} ->
     ?LOG_DEBUG("DB already exists: ~p", [DbName]);
    _Error ->
     {ok, Db} = couch_db:create(DbName, Options1), 
     ?LOG_DEBUG("DB created: ~p", [DbName])
    end,
    ensure_schedules_ddoc_exists(Db, <<"_design/getbydate">>),
    {ok,Db}.
    
open_schedules_db() ->
    DbName = ?l2b(couch_config:get("couchdb_scheduler", "schedules_db","schedules")),%can't name it _schedules underscore is limited only for _users _replicator                                                                                      %so the only way to workarround is to use db without underscore...
    {ok, SchedulesDb} =  ensure_schedules_db_exists(DbName, []),
    SchedulesDb.

exec_task(ServerPid)->
    ServerPid !  {exectask,<<"something">>},
    StartTaskTimer = erlang:send_after(10000, ServerPid, {exectask,<<"something else">>}),
    {ok,StartTaskTimer}.

do_earlier_tasks(State)->
  %Get all tasks with schedule_time on past and execute them
  %...Make it configurable if actual execute or just delete past tasks

{Db,ServerPid} = State,
    ?LOG_DEBUG("do_earlier_tasks",[]),
  timer:sleep(1000),
       A=exec_task(ServerPid),
         ?LOG_DEBUG("what exec ~p",[A]),
  timer:sleep(1000),
  
  Q=couch_mrview:query_view(Db, <<"_design/getbydate">>, <<"returnpasttasks">>),
  ?LOG_DEBUG("Query return ~p",[Q]),
  
    {ok,{A,State}}.

start_link() ->
    ?LOG_DEBUG("chronos_daemon: started..", []),
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    StartExamineTimer = erlang:send_after(6000, self(), examine),
    ?LOG_DEBUG("Init gen pid ~p",[self()]),
    Db=open_schedules_db(),
    {ok,{StartExamineTimer,Db,self()}}.

handle_info({exectask,What},State)->
?LOG_DEBUG("exec task ~p", [What]),
      {noreply,State};      
handle_info(examine,State)->
  {ExamineTimer,Db,ServerPid}=State,
  erlang:cancel_timer(ExamineTimer),
  ?LOG_DEBUG("Just in time ", []),
  %TODO Open every doc in schedules db and... that may takes more than a examine_period() on large db...
  %but no problem because examine restarted after...

  %Get all tasks with schedule_time on past and execute them
  %...Make it configurable if actual execute or delete past tasks

 _Pid = spawn_link(?MODULE,do_earlier_tasks,[{Db,ServerPid}]),
% do i need the Pid?
 
%schedule (erlang:send_after) all tasks that have a schedule_time at the next examine_period()

  %Restart examine timer
  ExamineAtTimer = erlang:send_after(examine_period(), self(), examine),
  {noreply,{ExamineAtTimer,Db,ServerPid}};

handle_info(_Msg, State) ->
    {noreply, State}.

handle_call(_Req, _From, State) ->
    {noreply, State}.

%unused gen_server staff
terminate(_Reason, _Srv) ->
    ok.

handle_cast(_Msg, State) ->
    {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
