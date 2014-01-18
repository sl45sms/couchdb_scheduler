-module(chronos_utils).
-include_lib("couch/include/couch_db.hrl").
-export([examine_period/0,open_schedules_db/0,open_db/1]).


-define(SCHEDULES_DB_DOC_RETURNPAST_FUN,<<"
function(doc){ScheduleDate= new Date(doc.schedule_time);MyDate = new Date();if (ScheduleDate<MyDate) emit('PAST '+doc.schedule_time, doc._rev);}
">>).

-define(SCHEDULES_DB_DOC_RETURNFUTURE_FUN,<<"
function(doc){ScheduleDate= new Date(doc.schedule_time);MyDate = new Date();if (ScheduleDate>MyDate) emit(doc.schedule_time+' '+ScheduleDate.toString(), doc._rev);}
">>).

examine_period()->
     list_to_integer(couch_config:get("couchdb_scheduler", "examine","60000")).

%may put this funs on another source (schedule_utils.erl?)
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


open_db(DbName)->
  Options = [{user_ctx, #user_ctx{roles=[<<"_admin">>]}}, nologifmissing],
   Db = case couch_db:open(DbName, Options) of
    {ok, MDb} ->
     ?LOG_DEBUG("Open db: ~p", [DbName]),
     MDb;
    _Error ->
     ?LOG_DEBUG("DB won't exist: ~p", [DbName]),
     error
    end,
 {ok, Db}.
