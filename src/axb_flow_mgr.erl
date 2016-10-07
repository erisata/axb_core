%/--------------------------------------------------------------------
%| Copyright 2015-2016 Erisata, UAB (Ltd.)
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
%%% Behaviour for a flow manager.
%%%
-module(axb_flow_mgr).
-behaviour(gen_fsm).
-compile([{parse_transform, lager_transform}]).
-export([start_link/5, info/3, register_flow/4, unregister_flow/3, flow_started/5, flow_online/4, flow_online/3]).
-export([init/1, handle_sync_event/4, handle_event/3, handle_info/3, terminate/3, code_change/4]).
-export([waiting/2, ready/2]).
-include("axb.hrl").

-define(REG(NodeName, FlowMgrName), {n, l, {?MODULE, NodeName, FlowMgrName}}).
-define(REF(NodeName, FlowMgrName), {via, gproc, ?REG(NodeName, FlowMgrName)}).   % TODO: Via axb, as in adapter.

-define(WAIT_INFO_DELAY, 5000).


%%% ============================================================================
%%% Callback definitions.
%%% ============================================================================

%%
%%  This callback is invoked on the manager process startup, and should return
%%  a list of flows to wait before considering the manager ready.
%%
-callback init(
        Args :: term()
    ) ->
        {ok, [Domain :: atom()], [FlowToWait :: module()], State :: term()}.


%%
%%  This callback notifies the flow manager about changed flow states.
%%
-callback flow_changed(
        FlowName    :: axb_flow(),
        Online      :: boolean(),
        State       :: term()
    ) ->
        ok.


%%
%%  This callback is invoked on code upgrades.
%%
-callback code_change(
        OldVsn  :: term(),
        State   :: term(),
        Extra   :: term()
    ) ->
        ok.



%%% ============================================================================
%%% Public API.
%%% ============================================================================

%%
%%  Start this flow manager.
%%
start_link(NodeName, FlowMgrName, CBModule, Args, Opts) ->
    gen_fsm:start_link(?REF(NodeName, FlowMgrName), ?MODULE, {NodeName, FlowMgrName, CBModule, Args}, Opts).


%%
%%  Get adapter's info.
%%
-spec info(
        NodeName :: atom(),
        Module   :: module(),
        What     :: all | flows | details
    ) ->
        {ok, Info :: term()}.

info(NodeName, FlowMgrName, What) ->
    gen_fsm:sync_send_all_state_event(?REF(NodeName, FlowMgrName), {info, What}).


%%
%%  Register new flow to this manager.
%%  This function must be called from the registering process.
%%
register_flow(NodeName, FlowMgrName, FlowDomain, FlowName) ->
    FlowPid = self(),
    gen_fsm:sync_send_all_state_event(?REF(NodeName, FlowMgrName), {register_flow, FlowDomain, FlowName, FlowPid}).



%%
%%  Unregister the flow from this manager.
%%
unregister_flow(NodeName, FlowMgrName, FlowName) ->
    gen_fsm:sync_send_all_state_event(?REF(NodeName, FlowMgrName), {unregister_flow, FlowName}).


%%
%%  Flows call this function to report them started.
%%  This is used for accounting them.
%%
flow_started(NodeName, FlowMgrName, FlowDomain, FlowName, _Opts) ->
    FlowPid = self(),
    true = ets:insert_new(?MODULE, {FlowPid, NodeName, FlowMgrName, FlowDomain, FlowName}),
    true = erlang:link(gproc:where(?REG(NodeName, FlowMgrName))),
    ok.


%%
%%  Change flow status for the specific flow manager.
%%
-spec flow_online(
        NodeName  :: atom(),
        Module    :: module(),
        FlowNames :: FlowName | Domain | all,
        Online    :: boolean()
    ) ->
        ok
    when
        FlowName :: axb_flow(),
        Domain :: axb_domain().

flow_online(NodeName, FlowMgrName, FlowNames, Online) ->
    gen_fsm:sync_send_all_state_event(?REF(NodeName, FlowMgrName), {flow_online, FlowNames, Online}).


%%
%%  Checks, if the flow is online or not.
%%  This function is executed in the caller's process.
%%
flow_online(NodeName, FlowMgrName, FlowName) ->
    Flows = gproc:lookup_value(?REG(NodeName, FlowMgrName)),
    lists:member({FlowName, true}, Flows).



%%% ============================================================================
%%% Internal data structures.
%%% ============================================================================

%%
%%  Represents single flow type (not a flow instance).
%%
-record(flow, {
    name    :: axb_flow(),      %% Flow name.
    pid     :: pid(),           %% PID of the flow supervisor.
    domain  :: axb_domain(),    %% Domain to which the flow belongs.
    online  :: boolean()        %% Is the flow online?
}).

%%
%%  FSM state data.
%%
-record(state, {
    node        :: atom(),                          % Node, to which the flow manager belongs.
    name        :: axb_flow_mgr(),                  % Name of the flow manager.
    cb_mod      :: module(),                        % Callback module for the flow manager implementation.
    cb_state    :: term(),                          % Callback state for the flow manager implementation.
    domains     :: [axb_domain()],                  % Domains, supported in this flow manager.
    flows       :: [#flow{}],                       % Flows, managed by this manager.
    waiting_tr  :: gen_fsm:reference() | undefined  % Waiting timer reference (if any) in order to cancel the timer before the new one is set or after waiting state is left
}).



%%% ============================================================================
%%% Callbacks for `gen_fsm`.
%%% ============================================================================


%%
%%
%%
init({NodeName, FlowMgrName, CBModule, Args}) ->
    erlang:process_flag(trap_exit, true),
    case ets:info(?MODULE, name) of
        undefined ->
            ets:new(?MODULE, [set, public, named_table, {write_concurrency,true}, {read_concurrency, true}]); % TODO: Move ETS table to axb app.
        _ ->
            ok
    end,
    case CBModule:init(Args) of
        {ok, Domains, FlowsToWait, CBState} ->
            Flows = [ #flow{name = F, pid = undefined, domain = undefined, online = false} || F <- FlowsToWait ],
            StateData = #state{
                node        = NodeName,
                name        = FlowMgrName,
                cb_mod      = CBModule,
                cb_state    = CBState,
                domains     = Domains,
                flows       = Flows,
                waiting_tr  = undefined
            },
            ok = publish_attrs(StateData),
            {ok, NewStateData} = notify_changes(Flows, StateData),
            {next_state, NextState, NewStateData2} = case have_all_deps(NewStateData) of
                true  -> ready(enter, NewStateData);
                false -> waiting(enter, NewStateData)
            end,
            {ok, NextState, NewStateData2};
        {stop, Reason} ->
            {stop, Reason};
        ignore ->
            ignore
    end.


%%
%%  The `waiting` state.
%%
waiting(enter, StateData) ->
    NewStateData = cancel_waiting_timeout(StateData),
    NewRef = gen_fsm:send_event_after(?WAIT_INFO_DELAY, waiting_timeout),
    {next_state, waiting, NewStateData#state{waiting_tr = NewRef}};

waiting(waiting_timeout, StateData = #state{flows = Flows}) ->
    MissingFlows = [ N || #flow{name = N, pid = undefined} <- Flows ],
    lager:info("Still waiting for flows ~p.", [MissingFlows]),
    waiting(enter, StateData#state{waiting_tr = undefined}).


%%
%%  The `ready` state.
%%
ready(enter, StateData = #state{node = NodeName, name = FlowMgrName, domains = Domains, flows = Flows}) ->
    StateDataAfterTimeCancel = cancel_waiting_timeout(StateData),
    FlowNames = [ FlowName || #flow{name = FlowName} <- Flows ],
    {ok, FlowStatuses} = axb_node:register_flow_mgr(NodeName, FlowMgrName, FlowNames, []),
    UpdateFlowStatus = fun ({Flow = #flow{name = FlowName}, {FlowName, Online}}) ->
        Flow#flow{online = Online}
    end,
    NewFlows = lists:map(UpdateFlowStatus, lists:zip(Flows, FlowStatuses)),
    %
    % Publish flow statuses.
    StateDataWithNewFlows = StateDataAfterTimeCancel#state{
        flows = NewFlows
    },
    ok = publish_attrs(StateDataWithNewFlows),
    {ok, StateDataAfterNotify} = notify_changes(NewFlows, StateDataWithNewFlows),
    %
    % Update stats.
    ok = axb_stats:flow_mgr_registered(NodeName, FlowMgrName, Domains),
    lager:debug("Flow manager ~p is ready at node ~p.", [FlowMgrName, NodeName]),
    {next_state, ready, StateDataAfterNotify}.


handle_sync_event({register_flow, FlowDomain, FlowName, FlowPid}, From, StateName, StateData) ->
    #state{node = NodeName, name = FlowMgrName, flows = Flows, domains = Domains} = StateData,
    true = lists:member(FlowDomain, Domains),
    Register = fun (NewFlows, Online) ->
        true = erlang:link(FlowPid),
        ok = axb_stats:flow_registered(NodeName, FlowMgrName, FlowDomain, FlowName),
        NewStateData = StateData#state{flows = NewFlows},
        case StateName of
            waiting ->
                gen_fsm:reply(From, {ok, Online}),
                case have_all_deps(NewStateData) of
                    true  -> ready(enter, NewStateData);
                    false -> waiting(enter, NewStateData)
                end;
            _ ->
                {reply, {ok, Online}, StateName, NewStateData}
        end
    end,
    case lists:keyfind(FlowName, #flow.name, Flows) of
        false ->
            % New Flow registered.
            Online = StateName =/= waiting, % NOTE: Only predefined flows are started offline initially.
            NewFlow = #flow{
                name   = FlowName,
                pid    = FlowPid,
                domain = FlowDomain,
                online = Online
            },
            Register([NewFlow | Flows]);
        #flow{pid = FlowPid, online = Online} = OldFlow ->
            % Existing Flow re-registered with the same PID, do almost nothing.
            NewFlow = OldFlow#flow{
                domain = FlowDomain
            },
            NewStateData = StateData#state{
                flows = lists:keyreplace(FlowName, #flow.name, Flows, NewFlow)
            },
            {reply, {ok, Online}, StateName, NewStateData};
        #flow{pid = undefined, online = Online} = OldFlow ->
            % New Flow registered, or re-registered after a crash.
            NewFlow = OldFlow#flow{
                pid    = FlowPid,
                domain = FlowDomain
            },
            Register(lists:keyreplace(FlowName, #flow.name, Flows, NewFlow), Online);
        #flow{} ->
            {reply, {error, already_registered}, StateName, StateData}
    end;

handle_sync_event({unregister_flow, FlowName}, _From, StateName, StateData) ->
    #state{name = FlowMgrName, flows = Flows} = StateData,
    case lists:keytake(FlowName, #flow.name, Flows) of
        false ->
            lager:warning("Attempt to unregister unknown flow ~p from ~p.", [FlowName, FlowMgrName]),
            {reply, ok, StateName, StateData};
        {value, #flow{pid = Pid}, NewFlows} ->
            lager:info("Unregistering flow ~p, pid=~p from ~p.", [FlowName, Pid, FlowMgrName]),
            true = erlang:unlink(Pid),
            NewStateData = StateData#state{flows = NewFlows},
            {reply, ok, StateName, NewStateData}
    end;

handle_sync_event({info, What}, _From, StateName, StateData) ->
    #state{
        domains = Domains,
        flows = Flows
    } = StateData,
    Reply = case What of
        flows ->
            {ok, [
                {N, flow_status(F)} || F = #flow{name = N} <- Flows
            ]};
        domains ->
            {ok, [
                {D, undefined} || D <- Domains
            ]};
        details ->
            {ok, [
                {flows, [
                    {N, [
                        {status, flow_status(F)},
                        {domain, D}
                    ]}
                    || F = #flow{name = N, domain = D} <- Flows
                ]}
            ]}
    end,
    {reply, Reply, StateName, StateData};

handle_sync_event({flow_online, FlowNames, Online}, _From, StateName, StateData) ->
    #state{
        node  = NodeName,
        name  = FlowMgrName,
        flows = Flows
    } = StateData,
    lager:debug("Updating flow statuses, names=~p, online=~p", [FlowNames, Online]),
    UpdateFlowStatus = fun
        (F = #flow{name = N, domain = D, online = O}, {UpdatedFlows, FlowChanges}) when O =/= Online ->
            case (FlowNames =:= all) or (FlowNames =:= N) or (FlowNames =:= D) of
                true ->
                    NewFlow = F#flow{online = Online},
                    {[NewFlow | UpdatedFlows], [NewFlow | FlowChanges]};
                false ->
                    {[F | UpdatedFlows], FlowChanges}
            end;
        (F = #flow{online = O}, {UpdatedFlows, FlowChanges}) when O =:= Online ->
            {[F | UpdatedFlows], FlowChanges}
    end,
    {NewFlows, FlowChanges} = lists:foldl(UpdateFlowStatus, {[], []}, Flows),
    NewStateData = StateData#state{flows = lists:reverse(NewFlows)},
    ok = publish_attrs(NewStateData),
    ok = axb_node_events:node_state_changed(NodeName, {flow_mgr, FlowMgrName, flow_state}),
    {ok, StateDataAfterNotify} = notify_changes(FlowChanges, NewStateData),
    {reply, ok, StateName, StateDataAfterNotify}.


%%
%%  All-state asynchronous events.
%%
handle_event(_Event, StateName, StateData) ->
    {next_state, StateName, StateData}.


%%
%%  Other messages.
%%
handle_info({'EXIT', FromPid, Reason}, StateName, StateData) when is_pid(FromPid) ->
    #state{
        node = NodeName,
        flows = Flows
    } = StateData,
    case ets:lookup(?MODULE, FromPid) of
        [{_FlowPid, NodeName, FlowMgrName, FlowDomain, FlowName}]->
            case Reason of
                normal ->
                    {next_state, StateName, StateData};
                _ ->
                    lager:error(
                        "Flow ~p terminated with reason=~p at ~p:~p:~p",
                        [FlowName, Reason, NodeName, FlowMgrName, FlowDomain]
                    ),
                    ok = axb_stats:flow_executed(NodeName, FlowMgrName, FlowDomain, FlowName, error),
                    true = ets:delete(?MODULE, FromPid),
                    {next_state, StateName, StateData}
            end;
        [] ->
            case lists:keyfind(FromPid, #flow.pid, Flows) of
                Flow = #flow{name = FlowName} ->
                    lager:warning("Flow terminated, name=~p, pid=~p, reason=~p", [FlowName, FromPid, Reason]),
                    NewFlows = lists:keyreplace(FlowName, #flow.name, Flows, Flow#flow{pid = undefined}),
                    {next_state, StateName, StateData#state{flows = NewFlows}};
                false ->
                    case Reason of
                        normal ->
                            {next_state, StateName, StateData};
                        _ ->
                            lager:warning("Linked process ~p terminated, exiting with reason ~p.", [FromPid, Reason]),
                            {stop, Reason, StateData}
                    end
            end
    end;

handle_info(_Request, StateName, StateData) ->
    {next_state, StateName, StateData}.


%%
%%  Termination.
%%
terminate(Reason, StateName, #state{node = NodeName, name = FlowMgrName}) ->
    lager:info(
        "Flow manager ~p:~p is terminating at state ~p with reason ~p.",
        [NodeName, FlowMgrName, StateName, Reason]
    ),
    ok.


%%
%%  Code upgrades.
%%
code_change(OldVsn, StateName, StateData = #state{cb_mod = CBModule, cb_state = CBState}, Extra) ->
    {ok, NewCBState} = CBModule:code_change(OldVsn, CBState, Extra),
    {ok, StateName, StateData#state{cb_state = NewCBState}}.



%%% ============================================================================
%%% Internal functions.
%%% ============================================================================

%%
%%  Check, if we have all deps registered.
%%
have_all_deps(#state{flows = Flows}) ->
    FlowsMissing = lists:keymember(undefined, #flow.pid, Flows),
    not FlowsMissing.


%%
%%  Determine flow_mgr's status.
%%
flow_status(#flow{pid = undefined})                            -> down;
flow_status(#flow{pid = Pid, online = true }) when is_pid(Pid) -> online;
flow_status(#flow{pid = Pid, online = false}) when is_pid(Pid) -> offline.


%%
%%  Publish some data in gproc for faster access.
%%
publish_attrs(#state{node = NodeName, name = FlowMgrName, flows = Flows}) ->
    FlowStatuses = [ {N, O} || #flow{name = N, online = O} <- Flows],
    true = gproc:set_value(?REG(NodeName, FlowMgrName), FlowStatuses),
    ok.


%%
%%
%%
notify_changes(ChangedFlows, StateData = #state{cb_mod = CBModule, cb_state = CBState}) ->
    NotifyChanges = fun (#flow{name = N, online = O}, CBS) ->
        case catch CBModule:flow_changed(N, O, CBS) of
            {ok, NewCBS} ->
                NewCBS;
            {error, Reason} ->
                lager:error("Failed to change flow ~p status to online=~p, reason=~p", [N, O, Reason]),
                CBS;
            {'EXIT', Reason} ->
                lager:error("Failed to change flow ~p status to online=~p, reason=~p", [N, O, Reason]),
                CBS;
            Reason ->
                lager:error("Failed to change flow ~p status to online=~p, reason=~p", [N, O, Reason]),
                CBS
        end
    end,
    NewCBState = lists:foldr(NotifyChanges, CBState, ChangedFlows),
    {ok, StateData#state{cb_state = NewCBState}}.


%%
%%  Cancels the waiting_timeout timer, if one is set.
%%
cancel_waiting_timeout(StateData = #state{waiting_tr = undefined}) ->
    StateData;

cancel_waiting_timeout(StateData = #state{waiting_tr = Ref}) ->
    _ = gen_fsm:cancel_timer(Ref),
    StateData#state{waiting_tr = undefined}.



