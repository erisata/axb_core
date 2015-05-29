%/--------------------------------------------------------------------
%| Copyright 2015 Erisata, UAB (Ltd.)
%|
%| Licensed under the Apache License, Version 2.0 (the "License");
%| you may not use this file except in compliance with the License.
%| You may obtain a copy of the License at
%|
%|     http://www.apache.org/licenses/LICENSE-2.0
%|
%| Unless required by applicable law or agreed to in writing, software
%| distributed under the License is distributed on an "AS IS" BASIS,
%| WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%| See the License for the specific language governing permissions and
%| limitations under the License.
%\--------------------------------------------------------------------

%%%
%%% This is a generic behaviour for processing a message in the ESB.
%%%
%%% TODO: Report crash statistics, register the flow with the manager.
%%%
-module(axb_flow).
-behaviour(gen_fsm).
-compile([{parse_transform, lager_transform}]).
-export([start_sup/2, start_link/6, respond/1, respond/2, wait_response/2]).
-export([flow_id/0, route_id/0, client_ref/0, related_id/2]).
-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3, terminate/3, code_change/4]).
-export([active/2, active/3]).

-define(REF(FlowId), {via, gproc, {n, l, {?MODULE, FlowId}}}).
-define(FLOW_ID,     'axb_flow$flow_id').
-define(ROUTE_ID,    'axb_flow$route_id').
-define(CLIENT_REF,  'axb_flow$client_ref').
-define(ADD_RELATED, 'axb_flow$add_related').
-define(RESPONSE,    'axb_flow$response').


%%% ============================================================================
%%% Callback definitions.
%%% ============================================================================

%%
%%
%%
-callback init(
        Args :: term()
    ) ->
        {ok, StateName :: atom(), StateData :: term()} |
        {ok, StateName :: atom(), StateData :: term(), Timeout :: integer()} |
        {ok, StateName :: atom(), StateData :: term(), hibernate} |
        {stop, Reason :: term()} |
        ignore.

%%
%%
%%
-callback handle_event(
        Event       :: term(),
        StateName   :: atom(),
        StateData   :: term()
    ) ->
        {next_state, NextStateName, NewStateData} |
        {next_state, NextStateName, NewStateData, Timeout} |
        {next_state, NextStateName, NewStateData, hibernate} |
        {stop, Reason, NewStateData}
    when
        NextStateName :: atom(),
        NewStateData :: term(),
        Timeout :: integer(),
        Reason :: term().

%%
%%
%%
-callback handle_sync_event(
        Event       :: term(),
        From        :: term(),
        StateName   :: atom(),
        StateData   :: term()
    ) ->
        {reply, Reply, NextStateName, NewStateData} |
        {reply, Reply, NextStateName, NewStateData, Timeout} |
        {reply, Reply, NextStateName, NewStateData, hibernate} |
        {next_state, NextStateName, NewStateData} |
        {next_state, NextStateName, NewStateData, Timeout} |
        {next_state, NextStateName, NewStateData, hibernate} |
        {stop, Reason, Reply, NewStateData} |
        {stop, Reason, NewStateData}
    when
        Reply :: term(),
        NextStateName :: atom(),
        NewStateData :: term(),
        Timeout :: integer(),
        Reason :: term().

%%
%%
%%
-callback handle_info(
        Info        :: term(),
        StateName   :: atom(),
        StateData   :: term()
    ) ->
        {next_state, NextStateName, NewStateData} |
        {next_state, NextStateName, NewStateData, Timeout} |
        {next_state, NextStateName, NewStateData, hibernate} |
        {stop, Reason, NewStateData}
    when
        NextStateName :: atom(),
        NewStateData :: term(),
        Timeout :: integer(),
        Reason :: term().


%%
%%
%%
-callback terminate(
        Reason      :: term(),
        StateName   :: atom(),
        StateData   :: term()
    ) -> any().


%%
%%
%%
-callback code_change(
        OldVsn      :: term(),
        StateName   :: atom(),
        StateData   :: term(),
        Extra       :: term()
    ) ->
        {ok, StateName :: atom(), StateData :: term()}.



%%% ============================================================================
%%% API functions.
%%% ============================================================================

%%
%%  Start this flow under the specified supervisor.
%%
start_sup(StartFun, Opts) ->
    {ok, FlowId, RouteId} = resolve_ids(Opts),
    {ok, ClientRef} = resolve_client_ref(Opts),
    EnrichedOpts = [{flow_id, FlowId}, {route_id, RouteId}, {client, ClientRef} | Opts],
    case StartFun(EnrichedOpts) of
        {ok, _} ->
            {ok, FlowId};
        {error, Reason} ->
            {error, Reason}
    end.


%%
%%  Start link.
%%
start_link(NodeName, MgrModule, Domain, Module, FlowArgs, Opts) ->
    case axb_flow_mgr:flow_online(NodeName, MgrModule, Module) of
        true ->
            {ok, FlowId, RouteId} = resolve_ids(Opts),
            {ok, ClientRef} = resolve_client_ref(Opts),
            Args = {NodeName, MgrModule, Domain, Module, FlowArgs, FlowId, RouteId, ClientRef},
            gen_fsm:start_link(?REF(FlowId), ?MODULE, Args, Opts);
        false ->
            {error, flow_offline}
    end.


%% TODO: Delegates for all FSM functions.


%%
%%
%%
respond(Response) ->
    Client = erlang:get(?CLIENT_REF),
    Client ! {?RESPONSE, flow_id(), Response}.


%%
%%
%%
respond(Client, Response) ->
    Client ! {?RESPONSE, flow_id(), Response}.


%%
%%
%%
wait_response(FlowId, Timeout) ->
    receive
        {?RESPONSE, FlowId, Response} ->
            Response
    after Timeout ->
        {error, timeout}
    end.



%%% ============================================================================
%%% API functions for FSM process only.
%%% ============================================================================

%%
%%
%%
flow_id() ->
    erlang:get(?FLOW_ID).


%%
%%
%%
route_id() ->
    erlang:get(?ROUTE_ID).


%%
%%
%%
client_ref() ->
    erlang:get(?CLIENT_REF).


%%
%%
%%
related_id(Name, Value) ->
    AddRelated = case erlang:get() of
        undefined -> [{Name, Value}];
        Other     -> [{Name, Value} | Other]
    end,
    erlang:put(?ADD_RELATED, AddRelated),
    ok.



%%% ============================================================================
%%% Internal state.
%%% ============================================================================

-record(state, {
    node        :: term(),
    mod         :: module(),
    mgr         :: module(),
    dom         :: atom(),
    sub_name    :: atom(),
    sub_data    :: term(),
    flow_id     :: term(),
    route_id    :: term(),
    client_ref  :: term(),
    start_time  :: erlang:timestamp(),
    related     :: [{Name :: term(), RelatedId :: term()}]
}).



%%% ============================================================================
%%% Callbacks for `gen_fsm`.
%%% ============================================================================

%%
%%
%%
init({NodeName, MgrModule, Domain, Module, Args, FlowId, RouteId, ClientRef}) ->
    erlang:put(?FLOW_ID, FlowId),
    erlang:put(?ROUTE_ID, RouteId),
    erlang:put(?CLIENT_REF, ClientRef),
    lager:md([
        {flow,  FlowId},
        {route, RouteId}
    ]),
    StateData = #state{
        node = NodeName,
        mod = Module,
        mgr = MgrModule,
        dom = Domain,
        sub_name = undefined,
        sub_data = undefined,
        flow_id = FlowId,
        route_id = RouteId,
        client_ref = ClientRef,
        start_time = os:timestamp(),
        related = []
    },
    delegate(active, StateData, {Module, init, [Args]}).


%%
%%
%%
active(Event, StateData) ->
    #state{mod = Module, sub_name = SubName, sub_data = SubData} = StateData,
    delegate(active, StateData, {Module, SubName, [Event, SubData]}).


%%
%%
%%
handle_event(Event, StateName, StateData) ->
    #state{mod = Module, sub_name = SubName, sub_data = SubData} = StateData,
    delegate(StateName, StateData, {Module, handle_event, [Event, SubName, SubData]}).


%%
%%
%%
active(Event, From, StateData) ->
    #state{mod = Module, sub_name = SubName, sub_data = SubData} = StateData,
    delegate(active, StateData, {Module, SubName, [Event, From, SubData]}).


%%
%%
%%
handle_sync_event(Event, From, StateName, StateData) ->
    #state{mod = Module, sub_name = SubName, sub_data = SubData} = StateData,
    delegate(StateName, StateData, {Module, handle_sync_event, [Event, From, SubName, SubData]}).


%%
%%
%%
handle_info(Info, StateName, StateData) ->
    #state{mod = Module, sub_name = SubName, sub_data = SubData} = StateData,
    delegate(StateName, StateData, {Module, handle_info, [Info, SubName, SubData]}).


%%
%%
%%
terminate(Reason, StateName, StateData) ->
    #state{mod = Module, sub_name = SubName, sub_data = SubData} = StateData,
    delegate(StateName, StateData, {Module, terminate, [Reason, SubName, SubData]}).


%%
%%
%%
code_change(OldVsn, StateName, StateData, Extra) ->
    #state{mod = Module, sub_name = SubName, sub_data = SubData} = StateData,
    delegate(StateName, StateData, {Module, code_change, [OldVsn, SubName, SubData, Extra]}).



%%% ============================================================================
%%% Internal functions.
%%% ============================================================================

%%
%%
%%
delegate(StateName, StateData, {Module, Function, Args}) ->
    #state{
        node       = NodeName,
        mgr        = MgrModule,
        dom        = Domain,
        start_time = StartTime,
        related    = Related
    } = StateData,
    ok = related_ids_setup(),
    Result = erlang:apply(Module, Function, Args),
    NewRelated = related_ids_collect(Related),
    case {Function, Result} of
        {_, {ok, NextSubName, NewSubData}} ->
            {ok, StateName, update_sub(StateData, NextSubName, NewSubData, NewRelated)};
        {_, {ok, NextSubName, NewSubData, TimeoutOrHibernate}} ->
            {ok, StateName, update_sub(StateData, NextSubName, NewSubData, NewRelated), TimeoutOrHibernate};
        {_, {reply, Reply, NextSubName, NewSubData}} ->
            {reply, Reply, StateName, update_sub(StateData, NextSubName, NewSubData, NewRelated)};
        {_, {reply, Reply, NextSubName, NewSubData, TimeoutOrHibernate}} ->
            {reply, Reply, StateName, update_sub(StateData, NextSubName, NewSubData, NewRelated), TimeoutOrHibernate};
        {_, {next_state, NextSubName, NewSubData}} ->
            {next_state, StateName, update_sub(StateData, NextSubName, NewSubData, NewRelated)};
        {_, {next_state, NextSubName, NewSubData, TimeoutOrHibernate}} ->
            {next_state, StateName, update_sub(StateData, NextSubName, NewSubData, NewRelated), TimeoutOrHibernate};
        {_, {stop, Reason, Reply, NewSubData}} ->
            DurationUS = timer:now_diff(os:timestamp(), StartTime),
            ok = axb_stats:flow_executed(NodeName, MgrModule, Domain, Module, DurationUS),
            {stop, Reason, Reply, update_sub(StateData, NewSubData, NewRelated)};
        {_, {stop, Reason, NewSubData}} ->
            DurationUS = timer:now_diff(os:timestamp(), StartTime),
            ok = axb_stats:flow_executed(NodeName, MgrModule, Domain, Module, DurationUS),
            {stop, Reason, update_sub(StateData, NewSubData, NewRelated)};
        {terminate, Any} ->
            Any
    end.


%%
%%
%%
update_sub(StateData, NextSubName, NewSubData, NewRelated) ->
    StateData#state{
        sub_name = NextSubName,
        sub_data = NewSubData,
        related = NewRelated
    }.


%%
%%
%%
update_sub(StateData, NewSubData, NewRelated) ->
    StateData#state{
        sub_data = NewSubData,
        related = NewRelated
    }.


%%
%%
%%
resolve_ids(Opts) ->
    FlowId = case proplists:get_value(flow_id, Opts) of
        undefined ->
            make_id();
        SuppliedFlowId ->
            SuppliedFlowId
    end,
    RouteId = case proplists:get_value(route_id, Opts) of
        undefined ->
            case route_id() of
                undefined ->
                    FlowId;
                ClientFlowId ->
                    ClientFlowId
            end;
        ClientRouteId ->
            ClientRouteId
    end,
    {ok, FlowId, RouteId}.


%%
%%
%%
resolve_client_ref(Opts) ->
    ClientRef = case proplists:get_value(client, Opts) of
        undefined ->
            self();
        SuppliedClientRef ->
            SuppliedClientRef
    end,
    {ok, ClientRef}.


%%
%%
%%
make_id() ->
    IdTerm = {node(), erlang:now()},
    SHA = crypto:hash(sha, erlang:term_to_binary(IdTerm)),
    lists:flatten([io_lib:format("~2.16.0B", [X]) || X <- binary_to_list(SHA)]).


%%
%%
%%
related_ids_setup() ->
    erlang:put(?ADD_RELATED, []),
    ok.


%%
%%
%%
related_ids_collect(Related) ->
    AddRelated = erlang:erase(?ADD_RELATED),
    AddRelated ++ Related.


