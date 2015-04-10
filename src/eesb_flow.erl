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
-module(eesb_flow).
-behaviour(gen_fsm).
-export([describe/3, default/4, start_sup/4, start_link/4]).
-export([flow_id/0, route_id/0, related_id/2]).
-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3, terminate/3, code_change/4]).
-export([active/2, active/3]).

-define(REF(FlowId), {via, gproc, {n, l, {?MODULE, FlowId}}}).
-define(FLOW_ID,  'eesb_flow$flow_id').
-define(ROUTE_ID, 'eesb_flow$route_id').


%% =============================================================================
%%  Callback definitions.
%% =============================================================================

-callback handle_describe(
        NodeName    :: term(),
        What        :: start_spec | sup_spec | meta
    ) ->
        {ok, Info :: term()}.


-callback init(
        Args :: term()
    ) ->
        {ok, State :: term()}.



%% =============================================================================
%%  API functions.
%% =============================================================================

%%
%%
%%
describe(NodeName, FlowModule, What) ->
    case FlowModule:handle_describe(NodeName, What) of
        {ok, Info} ->
            {ok, Info};
        {error, Reason} ->
            {error, Reason}
    end.


%%
%%  Default describe implementation.
%%
default(NodeName, FlowModule, start_spec, _Opts) ->
    SpecId = {?MODULE, NodeName, FlowModule},
    StartSpec = {?MODULE, start_link, [NodeName, FlowModule]},
    ChildSpec = {SpecId, StartSpec, transient, brutal_kill, worker, [?MODULE, FlowModule]},
    {ok, ChildSpec};

default(NodeName, FlowModule, sup_spec, _Opts) ->
    ChildSpec = eesb_flow_sup_sofo:start_spec(
        {eesb_flow_sup_sofo, NodeName, FlowModule},
        {eesb_flow_sup_sofo, start_link, [NodeName, FlowModule]}
    ),
    {ok, ChildSpec};

default(NodeName, FlowModule, meta, _Opts) ->
    {ok, [
        {node, NodeName},
        {flow, FlowModule}
    ]}.


%%
%%  Start this flow under the specified supervisor.
%%
start_sup(NodeName, FlowModule, Args, Opts) ->
    {ok, FlowId, RouteId} = resolve_ids(Opts),
    NewOpts = [{flow_id, FlowId}, {route_id, RouteId} | Opts],
    {ok, _} = eesb_flow_sup:start_flow(NodeName, FlowModule, Args, NewOpts),
    {ok, FlowId}.


%%
%%  Start link.
%%
start_link(NodeName, FlowModule, Args, Opts) ->
    {ok, FlowId, RouteId} = resolve_ids(Opts),
    gen_fsm:start_link(?REF(FlowId), ?MODULE, {NodeName, FlowModule, Args, FlowId, RouteId}, Opts).


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
related_id(Name, Value) ->
    % TODO.
    ok.



%% =============================================================================
%%  Internal state.
%% =============================================================================

-record(state, {
    node     :: term(),
    mod      :: module(),
    sub_name :: atom(),
    sub_data :: term(),
    flow_id  :: term(),
    route_id :: term(),
    related  :: [{Name :: term(), RelatedId :: term()}]
}).



%% =============================================================================
%%  Callbacks for `gen_fsm`.
%% =============================================================================

%%
%%
%%
init({NodeName, FlowModule, Args, FlowId, RouteId}) ->
    erlang:put(?FLOW_ID, FlowId),
    erlang:put(?ROUTE_ID, RouteId),
    lager:md([
        {flow,  FlowId},
        {route, RouteId}
    ]),
    {ok, SubName, SubData} = FlowModule:init(Args),
    StateName = active,
    StateData = #state{
        node = NodeName,
        mod = FlowModule,
        sub_name = SubName,
        sub_data = SubData,
        flow_id = FlowId,
        route_id = RouteId,
        related = []
    },
    {ok, StateName, StateData}.


%%
%%
%%
active(Event, StateData) ->
    #state{mod = FlowModule, sub_name = SubName, sub_data = SubData} = StateData,
    update_sub_result(active, StateData, FlowModule:SubName(Event, SubData)).


%%
%%
%%
handle_event(Event, StateName, StateData) ->
    #state{mod = FlowModule, sub_name = SubName, sub_data = SubData} = StateData,
    update_sub_result(StateName, StateData, FlowModule:handle_event(Event, SubName, SubData)).


%%
%%
%%
active(Event, From, StateData) ->
    #state{mod = FlowModule, sub_name = SubName, sub_data = SubData} = StateData,
    update_sub_result(active, StateData, FlowModule:SubName(Event, From, SubData)).


%%
%%
%%
handle_sync_event(Event, From, StateName, StateData) ->
    #state{mod = FlowModule, sub_name = SubName, sub_data = SubData} = StateData,
    update_sub_result(StateName, StateData, FlowModule:handle_event(Event, From, SubName, SubData)).


%%
%%
%%
handle_info(Info, StateName, StateData) ->
    #state{mod = FlowModule, sub_name = SubName, sub_data = SubData} = StateData,
    update_sub_result(StateName, StateData, FlowModule:handle_info(Info, SubName, SubData)).


%%
%%
%%
terminate(Reason, _StateName, StateData) ->
    #state{mod = FlowModule, sub_name = SubName, sub_data = SubData} = StateData,
    FlowModule:terminate(Reason, SubName, SubData).


%%
%%
%%
code_change(OldVsn, StateName, StateData, Extra) ->
    #state{mod = FlowModule, sub_name = SubName, sub_data = SubData} = StateData,
    {ok, NextSubName, NewSubData} = FlowModule:code_change(OldVsn, SubName, SubData, Extra),
    {ok, StateName, update_sub(StateData, NextSubName, NewSubData)}.



%% =============================================================================
%%  Internal functions.
%% =============================================================================

%%
%%
%%
update_sub(StateData, NextSubName, NewSubData) ->
    StateData#state{
        sub_name = NextSubName,
        sub_data = NewSubData
    }.


%%
%%
%%
update_sub(StateData, NewSubData) ->
    StateData#state{
        sub_data = NewSubData
    }.


%%
%%
%%
update_sub_result(StateName, StateData, Result) ->
    case Result of
        {reply, Reply, NextSubName, NewSubData} ->
            NewStateData = update_sub(StateData, NextSubName, NewSubData),
            {reply, Reply, StateName, NewStateData};
        {reply, Reply, NextSubName, NewSubData, TimeoutOrHibernate} ->
            NewStateData = update_sub(StateData, NextSubName, NewSubData),
            {reply, Reply, StateName, NewStateData, TimeoutOrHibernate};
        {next_state, NextSubName, NewSubData} ->
            NewStateData = update_sub(StateData, NextSubName, NewSubData),
            {next_state, StateName, NewStateData};
        {next_state, NextSubName, NewSubData, TimeoutOrHibernate} ->
            NewStateData = update_sub(StateData, NextSubName, NewSubData),
            {next_state, StateName, NewStateData, TimeoutOrHibernate};
        {stop, Reason, Reply, NewSubData} ->
            NewStateData = update_sub(StateData, NewSubData),
            {stop, Reason, Reply, NewStateData};
        {stop, Reason, NewSubData} ->
            NewStateData = update_sub(StateData, NewSubData),
            {stop, Reason, NewStateData}
    end.


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
make_id() ->
    {node(), erlang:now()}.


