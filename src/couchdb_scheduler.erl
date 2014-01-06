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

create_schedule(_,_,_,_,_,[],_,Acc)->
                Acc;
create_schedule(UserName,DbName,DesignName,ScheduleFunName,DocID,ScheduleTime,Params,Acc) ->
               [RS|REST]=ScheduleTime,
               IsoTime=iso8601:format(RS),
               {ok,TaskUUID,ScheduleIsoTime}=create_schedule(UserName,DbName,DesignName,ScheduleFunName,DocID,IsoTime,Params),
         create_schedule(UserName,DbName,DesignName,ScheduleFunName,DocID,REST,Params,lists:append(Acc,[{[{uuid,TaskUUID},{isodate,ScheduleIsoTime}]}])).

create_schedule(UserName,DbName,DesignName,ScheduleFunName,DocID,ScheduleIsoTime,Params)->
    Db=open_schedules_db(),
    TaskID=couch_uuids:random(),
    CouchDB_UUID = ?l2b(couch_config:get("couchdb", "uuid")),
    try 
        CreationIsoTime=iso8601:format(now()),
        ScheduleID=?l2b([<<"schedule#">>,DbName,<<"#">>,DesignName,<<"#">>,ScheduleFunName,<<"#">>,DocID,<<"#at#">>,ScheduleIsoTime]),%TODO simpler? more complex?
        NewDoc = #doc{
          id=ScheduleID,
          body={[
                 {<<"_id">>, ScheduleID},
                 {<<"taskid">>, TaskID},
                 {<<"username">>, UserName},
                 {<<"db">>,DbName},
                 {<<"ddoc">>,DesignName },
                 {<<"fun">>,ScheduleFunName },
                 {<<"querystring">>,Params },
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
        path_parts=[DbName, <<"_design">>, DesignName, _schedules, ScheduleFunName,ScheduleTime,DocID],user_ctx = UserCtx
    }=Req, _, _) ->
    handle_schedules(DbName,DesignName,ScheduleFunName,ScheduleTime,DocID,UserCtx,Req);
handle_schedules(#httpd{
        path_parts=[DbName, <<"_design">>, DesignName, _schedules, ScheduleFunName,ScheduleTime],user_ctx = UserCtx
    }=Req, _, _) ->
    handle_schedules(DbName,DesignName,ScheduleFunName,ScheduleTime,<<"null">>,UserCtx,Req).
    
handle_schedules(DbName,DesignName,ScheduleFunName,ScheduleTime,DocID,UserCtx,Req) ->
     {user_ctx,UserName,_,_} = UserCtx,
      %TODO what todo for null UserName?
      QueryStringData={[{list_to_binary(Key),list_to_binary(Val)} ||{Key,Val} <-couch_httpd:qs(Req)]},
       ?LOG_DEBUG("Query = ~p", [QueryStringData]),
      ScheduleList = case iso8601:is_datetime(ScheduleTime) of
           true-> [iso8601:parse(ScheduleTime)];
           false->iso8601:parse_interval(ScheduleTime)
                       end,
     TaskIDS=create_schedule(UserName,DbName,DesignName,ScheduleFunName,DocID,ScheduleList,QueryStringData,[]),
     couch_httpd:send_json(Req, 200,{[{ok,<<"Scheduled">>},{docid,DocID},{tasks,TaskIDS}]}).
