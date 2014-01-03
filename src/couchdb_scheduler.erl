-module(couchdb_scheduler).

-export([handle_schedules/3]).

-include_lib("couch/include/couch_db.hrl").

ensure_schedules_db_exists(DbName, Options) ->
    Options1 = [{user_ctx, #user_ctx{roles=[<<"_admin">>]}}, nologifmissing | Options],
    case couch_db:open(DbName, Options1) of
    {ok, Db} ->
     ?LOG_DEBUG("DB already exists: ~p", [DbName]),
     {ok, Db};
    _Error ->
     {ok, Db} = couch_db:create(DbName, Options1), 
     ?LOG_DEBUG("DB created: ~p", [DbName]), 
     {ok, Db}
    end.

open_schedules_db() ->
    DbName = ?l2b(couch_config:get("couchdb_scheduler", "schedules_db","schedules")),%can't name it _schedules underscore is limited only for _users _replicator                                                                                      %so the only way to workarround is to use db without underscore...
    {ok, SchedulesDb} =  ensure_schedules_db_exists(DbName, []),
    SchedulesDb.

create_schedule(_,_,_,_,[],Acc)->
                Acc;
create_schedule(DbName,DDocName,ScheduleFunName,DocID,ScheduleTime,Acc) ->
               [RS|REST]=ScheduleTime,
               IsoTime=iso8601:format(RS),
               {ok,TaskUUID,ScheduleIsoTime}=create_schedule(DbName,DDocName,ScheduleFunName,DocID,IsoTime),
         create_schedule(DbName,DDocName,ScheduleFunName,DocID,REST,lists:append(Acc,[{uuid,TaskUUID},{isodate,ScheduleIsoTime}])).

create_schedule(DbName,DDocName,ScheduleFunName,DocID,ScheduleIsoTime)->
    Db=open_schedules_db(),
    TaskID=couch_uuids:random(),
    CouchDB_UUID = ?l2b(couch_config:get("couchdb", "uuid")),
    try 
        CreationIsoTime=iso8601:format(now()),%TODO ScheduleIsoTime>CreationIsoTime or throw error
        ScheduleID=?l2b([<<"schedule:">>,DbName,<<":">>,DDocName,<<":">>,ScheduleFunName,<<":">>,DocID,<<":at:">>,ScheduleIsoTime]),%TODO simpler? more complex?      
        NewDoc = #doc{
          id=ScheduleID,
          body={[
                 {<<"_id">>, ScheduleID},
                 {<<"taskid">>, TaskID},
                 {<<"db">>,DbName},
                 {<<"ddoc">>,DDocName },
                 {<<"fun">>,ScheduleFunName },
                 {<<"schedule_time">>,ScheduleIsoTime },
                 {<<"creation_time">>,CreationIsoTime },
                 {<<"doc">>, DocID},
                 {<<"performed">>, false},
                 {<<"couchdb_uuid">>, CouchDB_UUID} %daemon check this 
                ]}
         },

        DbWithoutValidationFunc = Db#db{ validate_doc_funs=[] },   
        case couch_db:update_doc(DbWithoutValidationFunc, NewDoc, []) of
            {ok, _} ->
                ?LOG_DEBUG("Schedule fun created for ~p:~p", [ScheduleFunName, DocID]),
                {ok, TaskID, ScheduleIsoTime};
            Error ->
                ?LOG_ERROR("Could not create schedule for ~p:~p Reason:", [ScheduleFunName, DocID, Error]),
                throw(could_not_create_schedule)
        end
    after
        couch_db:close(Db),
        TaskID
    end.


handle_schedules(#httpd{
        path_parts=[DbName, _, DDocName, _, ScheduleFunName,ScheduleTime,DocID]
    }=Req, _, _) ->
      %TODO? docid optional....
      ScheduleList = case iso8601:is_datetime(ScheduleTime) of
           true-> [iso8601:parse(ScheduleTime)];
           false->iso8601:parse_interval(ScheduleTime)
                       end,
     TaskIDS=create_schedule(DbName,DDocName,ScheduleFunName,DocID,ScheduleList,[]),
     couch_httpd:send_json(Req, 200,{[{ok,<<"Scheduled">>},{docid,DocID},{tasks,{TaskIDS}}]}).
