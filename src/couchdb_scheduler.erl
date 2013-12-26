-module(couchdb_scheduler).

-export([handle_schedules/3]).

-include_lib("couch/include/couch_db.hrl").

ensure_schedules_db_exists(DbName, Options) ->
    Options1 = [{user_ctx, #user_ctx{roles=[<<"_admin">>]}}, nologifmissing | Options],
    case couch_db:open(DbName, Options1) of
    {ok, Db} ->
     ?LOG_INFO("DB already exists: ~p", [DbName]),
     {ok, Db};
    _Error ->
     {ok, Db} = couch_db:create(DbName, Options1), 
     ?LOG_INFO("DB created: ~p", [DbName]), 
     {ok, Db}
    end.

open_schedules_db() ->
    DbName = ?l2b(couch_config:get("couchdb_scheduler", "schedules_db","schedules")),%can't name it _schedules underscore is limited only for _users _replicator                                                                                      %so the only way to workarround is to use db without underscore...
    {ok, AuthDb} =  ensure_schedules_db_exists(DbName, []),
    AuthDb.

create_schedule(DbName,DDocName,ScheduleFunName,DocID,ScheduleTime) ->
    Db=open_schedules_db(),
    TaskID=couch_uuids:random(),
    try 
       % {A1,A2,A3} = now(),%todo na sozo to creation time...

        ScheduleID=?l2b([<<"schedule:">>,DbName,<<":">>,DDocName,<<":">>,ScheduleFunName,<<":">>,DocID,<<":at:">>,ScheduleTime]),%TODO pio poliploko...
  
     %TODO na vazo mesa sto NewDoc kai to UID ths vashs sto trexon mhxanima oste na kserei o skeduler oti prepei na treksei se auto to mhxanima
     %na mporei na pernei kai parametrika _ oste opia mhxanh prolavei prolave...
      
        NewDoc = #doc{
          id=ScheduleID,
          body={[
                 {<<"_id">>, ScheduleID},
                 {<<"taskid">>, TaskID},
                 {<<"db">>,DbName},
                 {<<"ddoc">>,DDocName },
                 {<<"fun">>,ScheduleFunName },
                 {<<"datetime">>,ScheduleTime },
                 {<<"doc">>, DocID}
                ]}
         },

        DbWithoutValidationFunc = Db#db{ validate_doc_funs=[] },   
        case couch_db:update_doc(DbWithoutValidationFunc, NewDoc, []) of
            {ok, _} ->
                ?LOG_DEBUG("Schedule fun created for ~p:~p", [ScheduleFunName, DocID]),
                {ok, DocID, ScheduleTime};
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
      %TODO docid optional....
      %TODO parse ScheduleTime complete... %have to fix the iso8601 lib first
      [{sign,Sign},{years,Years},{months,Months},
     {days,Days},{hours,Hours},{minutes,Minutes},
     {seconds,Seconds}]=iso8601:parse_durations(ScheduleTime),
      Nm=list_to_integer(Minutes),
      IsoDate=iso8601:format(iso8601:add_time(calendar:now_to_datetime(now()),1 , Nm, 1)),
      {_,TaskID,_}=create_schedule(DbName,DDocName,ScheduleFunName,DocID,IsoDate),
       couch_httpd:send_json(Req, 200, {[{ok, <<"Scheduled">>},{taskid,TaskID},{at,IsoDate}]}).
