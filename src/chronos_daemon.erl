-module(chronos_daemon).
-include_lib("couch/include/couch_db.hrl").
-behaviour(gen_server).

-export([start_link/0,do_earlier_tasks/1,exec_task/1]).

%gen_server exports
-export([init/1, terminate/2, code_change/3]).
-export([handle_call/3, handle_cast/2, handle_info/2]).



exec_task({ServerPid,Db,DocID})->
%open the doc from schedules
{ok, Doc} = couch_db:open_doc(Db, DocID),
#doc{body = Body} = Doc,
{[{<<"_id">>,_DocID},
  {<<"taskid">>,TaskID},
  {<<"username">>,UserName},
  {<<"db">>,TargetDb},
  {<<"ddoc">>,TargetDDoc},
  {<<"fun">>,TargetFun},
  {<<"querystring">>,Query},
  {<<"schedule_time">>,_ScheduleTime},
  {<<"creation_time">>,_CreationTime},
  {<<"doc">>,TargetDoc},
  {<<"performed">>,_},
  {<<"couchdb_uuid">>,_ServerUUID}]}=couch_compress:decompress(Body),

%Do stuf on target
{ok,TDb}=chronos_utils:open_db(TargetDb),
{ok,TDDoc} = couch_db:open_doc(TDb, <<"_design/",TargetDDoc/bitstring>>),
{ok,TDoc} = couch_db:open_doc(TDb, TargetDoc),
JsonDoc = couch_query_servers:json_doc(TDoc),
[<<"up">>, {NewJsonDoc}, {JsonResp0}] = couch_query_servers:ddoc_prompt(TDDoc, [<<"updates">>,TargetFun], [JsonDoc,<<"">>]),%TODO query prepei na exei thn morfh tou req?
%TODO cana case se periptosh pou den einai up
NewDoc = couch_doc:from_json_obj({NewJsonDoc}),
couch_doc:validate_docid(NewDoc#doc.id),
{ok, NewRev} = couch_db:update_doc(TDb, NewDoc, []),
NewRevStr = couch_doc:rev_to_str(NewRev),





%TODO delete shedule doc
#doc{id=DELDOCID}=Doc,
?LOG_DEBUG("delete this doc = ~p",[DELDOCID]), %Ok kanei delete alla fenete oti tou pasarei sinexeia to idio docID
#doc{revs={Start, [Rev|_]}}=Doc,
DelDoc = Doc#doc{revs={Start, [Rev]}, deleted=true},
{ok, [Result]} = couch_db:update_docs(Db, [DelDoc], []),
?LOG_DEBUG("delete doc have= ~p",[Result]),

?LOG_DEBUG("doc have= ~p",[NewRevStr]),
ok.



do_earlier_tasks(State)->
  %...Make it configurable if actual execute or just delete past tasks
{Db,ServerPid} = State,
    ?LOG_DEBUG("do_earlier_tasks",[]),
  timer:sleep(1000),
Q=couch_mrview:query_view(Db, <<"_design/getbydate">>, <<"returnpasttasks">>,[{limit, 1},{stale,false}]),
case Q of
{ok,[{meta,[{total,Total},{offset,_}]},{row,[{id,DocID},_,_]}]}->
     A=exec_task({ServerPid,Db,DocID}),
     ?LOG_DEBUG("what exec ~p",[A]),
     {ok,{A,State}};
{ok,[{meta,[{total,0},{offset,_}]}]}->
     ?LOG_DEBUG("No past tasks",[]),
     {ok,{0,State}}
end.    

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    StartExamineTimer = erlang:send_after(6000, self(), examine),
   % ?LOG_DEBUG("Init gen pid ~p",[self()]),
    Db=chronos_utils:open_schedules_db(),
    {ok,{StartExamineTimer,Db,self()}}.

            
handle_info(examine,State)->
  {ExamineTimer,Db,ServerPid}=State,
  erlang:cancel_timer(ExamineTimer),
  %TODO Open every doc in schedules db and... that may takes more than a examine_period() on large db...
  %but no problem because examine restarted after...

  %Get all tasks with schedule_time on past and execute them
  %...Make it configurable if actual execute or delete past tasks

  _Pid = spawn_link(?MODULE,do_earlier_tasks,[{Db,ServerPid}]),   
% do i need the Pid?
 
%schedule (erlang:send_after) all tasks that have a schedule_time at the next examine_period()

  %Restart examine timer
  ExamineAtTimer = erlang:send_after(chronos_utils:examine_period(), self(), examine),
  {noreply,{ExamineAtTimer,Db,ServerPid}};

handle_info(_Msg, State) ->
    {noreply, State}.

%unused gen_server staff
handle_call(_Req, _From, State) ->
    {noreply, State}.
    
terminate(_Reason, _Srv) ->
    ok.

handle_cast(_Msg, State) ->
    {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
