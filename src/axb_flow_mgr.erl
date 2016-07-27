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
%%% Behaviour for a flow manager.
%%%
%%% TODO: Change it to not use the FSM state timeouts to avoid race conditions.
%%%
-module(axb_flow_mgr).
-behaviour(gen_fsm).
-compile([{parse_transform, lager_transform}]).
-export([start_link/5, info/3, register_flow/5, unregister_flow/3, flow_started/5, flow_online/4, flow_online/3]).
-export([init/1, handle_sync_event/4, handle_event/3, handle_info/3, terminate/3, code_change/4]).
-export([waiting/2, ready/2]).

-define(REG(NodeName, Module), {n, l, {?MODULE, NodeName, Module}}).
-define(REF(NodeName, Module), {via, gproc, ?REG(NodeName, Module)}).

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
        FlowModule  :: module(),
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
start_link(NodeName, Module, CBModule, Args, Opts) ->
    gen_fsm:start_link(?REF(NodeName, Module), ?MODULE, {NodeName, Module, CBModule, Args}, Opts).


%%
%%  Get adapter's info.
%%
-spec info(
        NodeName :: atom(),
        Module   :: module(),
        What     :: all | flows | details
    ) ->
        {ok, Info :: term()}.

info(NodeName, Module, What) ->
    gen_fsm:sync_send_all_state_event(?REF(NodeName, Module), {info, What}).


%%
%%  Register new flow to this manager.
%%  This function must be called from the registering process.
%%
register_flow(NodeName, Module, FlowDomain, FlowModule, Online) ->
    FlowPid = self(),
    gen_fsm:sync_send_all_state_event(?REF(NodeName, Module), {register_flow, FlowDomain, FlowModule, Online, FlowPid}).



%%
%%  Unregister the flow from this manager.
%%
unregister_flow(NodeName, Module, FlowModule) ->
    gen_fsm:sync_send_all_state_event(?REF(NodeName, Module), {unregister_flow, FlowModule}).


%%
%%  Flows call this function to report them started.
%%  This is used for accounting them.
%%
flow_started(NodeName, Module, FlowDomain, FlowModule, _Opts) ->
    FlowPid = self(),
    true = ets:insert_new(?MODULE, {FlowPid, NodeName, Module, FlowDomain, FlowModule}),
    true = erlang:link(gproc:where(?REG(NodeName, Module))),
    ok.


%%
%%  Change flow status for the specific flow manager.
%%
-spec flow_online(
        NodeName  :: atom(),
        Module    :: module(),
        FlowNames :: FlowModule | Domain | all,
        Online    :: boolean()
    ) ->
        ok
    when
        FlowModule :: module(),
        Domain :: atom().

flow_online(NodeName, Module, FlowNames, Online) ->
    gen_fsm:sync_send_all_state_event(?REF(NodeName, Module), {flow_online, FlowNames, Online}).


%%
%%  Checks, if the flow is online or not.
%%  This function is executed in the caller's process.
%%
flow_online(NodeName, Module, FlowModule) ->
    Flows = gproc:lookup_value(?REG(NodeName, Module)),
    lists:member({FlowModule, true}, Flows).



%%% ============================================================================
%%% Internal data structures.
%%% ============================================================================

%%
%%  Represents single flow type (not a flow instance).
%%
-record(flow, {
    mod     :: module(),    %% Flow modue (and name).
    pid     :: pid(),       %% PID of the flow supervisor.
    domain  :: atom(),      %% Domain to which the flow belongs.
    online  :: boolean()    %% Is the flow online?
}).

%%
%%  FSM state data.
%%
-record(state, {
    node    :: atom(),
    mod     :: module(),    %% User-defined module for the flow manager (name).
    cbm     :: module(),    %% Callback module for the flow manager implementation.
    cbs     :: term(),      %% Callback state for the flow manager implementation.
    domains :: [atom()],    %% Domains, supported in this flow manager.
    flows   :: [#flow{}]    %% Flows, managed by this manager.
}).



%%% ============================================================================
%%% Callbacks for `gen_fsm`.
%%% ============================================================================


%%
%%
%%
init({NodeName, Module, CBModule, Args}) ->
    erlang:process_flag(trap_exit, true),
    case ets:info(?MODULE, name) of
        undefined ->
            ets:new(?MODULE, [set, public, named_table, {write_concurrency,true}, {read_concurrency, true}]);
        _ ->
            ok
    end,
    case CBModule:init(Args) of
        {ok, Domains, FlowsToWait, CBState} ->
            Flows = [ #flow{mod = F, pid = undefined, domain = undefined, online = false} || F <- FlowsToWait ],
            StateData = #state{
                node    = NodeName,
                mod     = Module,
                cbm     = CBModule,
                cbs     = CBState,
                domains = Domains,
                flows   = Flows
            },
            ok = publish_attrs(StateData),
            {ok, NewStateData} = notify_changes(Flows, StateData),
            case have_all_deps(NewStateData) of
                true  -> {ok, ready, NewStateData, 0};
                false -> {ok, waiting, NewStateData, ?WAIT_INFO_DELAY}
            end;
        {stop, Reason} ->
            {stop, Reason};
        ignore ->
            ignore
    end.


%%
%%  The `waiting` state.
%%
waiting(timeout, StateData = #state{flows = Flows}) ->
    MissingFlows = [ M || #flow{mod = M, pid = undefined} <- Flows ],
    lager:info("Still waiting for flows ~p.", [MissingFlows]),
    {next_state, waiting, StateData, ?WAIT_INFO_DELAY}.


%%
%%  The `ready` state.
%%
ready(timeout, StateData = #state{node = NodeName, mod = Module, domains = Domains}) ->
    ok = axb_node:register_flow_mgr(NodeName, Module, []),
    ok = axb_stats:flow_mgr_registered(NodeName, Module, Domains),
    lager:debug("Flow manager ~p is ready at node ~p.", [Module, NodeName]),
    {next_state, ready, StateData}.


handle_sync_event({register_flow, FlowDomain, FlowModule, Online, FlowPid}, _From, StateName, StateData) ->
    #state{node = NodeName, mod = Module, flows = Flows, domains = Domains} = StateData,
    true = lists:member(FlowDomain, Domains),
    NewFlow = #flow{mod = FlowModule, pid = FlowPid, domain = FlowDomain, online = Online},
    Register = fun (NewFlows) ->
        true = erlang:link(FlowPid),
        ok = axb_stats:flow_registered(NodeName, Module, FlowDomain, FlowModule),
        NewStateData = StateData#state{flows = NewFlows},
        case StateName of
            waiting ->
                case have_all_deps(NewStateData) of
                    true ->  {reply, ok, ready,   NewStateData, 0};
                    false -> {reply, ok, waiting, NewStateData, ?WAIT_INFO_DELAY}
                end;
            _ ->
                {reply, ok, StateName, NewStateData}
        end
    end,
    StateTimeout = case StateName of
        waiting -> ?WAIT_INFO_DELAY;
        ready   -> infinity
    end,
    case lists:keyfind(FlowModule, #flow.mod, Flows) of
        false ->
            Register([NewFlow | Flows]);
        NewFlow ->
            {reply, ok, StateName, StateData, StateTimeout};
        #flow{pid = undefined} ->
            Register(lists:keyreplace(FlowModule, #flow.mod, Flows, NewFlow));
        #flow{} ->
            {reply, {error, already_registered}, StateName, StateData, StateTimeout}
    end;

handle_sync_event({unregister_flow, FlowModule}, _From, StateName, StateData) ->
    #state{mod = Module, flows = Flows} = StateData,
    case lists:keytake(FlowModule, #flow.mod, Flows) of
        false ->
            lager:warning("Attempt to unregister unknown flow ~p from ~p.", [FlowModule, Module]),
            {reply, ok, StateName, StateData};
        {value, #flow{pid = Pid}, NewFlows} ->
            lager:info("Unregistering flow ~p, pid=~p from ~p.", [FlowModule, Pid, Module]),
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
                {M, flow_status(F)} || F = #flow{mod = M} <- Flows
            ]};
        domains ->
            {ok, [
                {D, undefined} || D <- Domains
            ]};
        details ->
            {ok, [
                {flows, [
                    {M, [
                        {status, flow_status(F)},
                        {domain, D}
                    ]}
                    || F = #flow{mod = M, domain = D} <- Flows
                ]}
            ]}
    end,
    {reply, Reply, StateName, StateData};

handle_sync_event({flow_online, FlowNames, Online}, _From, StateName, StateData = #state{flows = Flows}) ->
    lager:debug("Updating flow statuses, names=~p, online=~p", [FlowNames, Online]),
    UpdateFlowStatus = fun
        (F = #flow{mod = M, domain = D, online = O}, {UpdatedFlows, FlowChanges}) when O =/= Online ->
            case (FlowNames =:= all) or (FlowNames =:= M) or (FlowNames =:= D) of
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
        [{_FlowPid, NodeName, Module, FlowDomain, FlowModule}]->
            case Reason of
                normal ->
                    {next_state, StateName, StateData};
                _ ->
                    lager:error(
                        "Flow ~p terminated with reason=~p at ~p:~p:~p",
                        [FlowModule, Reason, NodeName, Module, FlowDomain]
                    ),
                    ok = axb_stats:flow_executed(NodeName, Module, FlowDomain, FlowModule, error),
                    true = ets:delete(?MODULE, FromPid),
                    {next_state, StateName, StateData}
            end;
        [] ->
            case lists:keyfind(FromPid, #flow.pid, Flows) of
                Flow = #flow{mod = FlowModule} ->
                    lager:warning("Flow terminated, module=~p, pid=~p, reason=~p", [FlowModule, FromPid, Reason]),
                    NewFlows = lists:keyreplace(FlowModule, #flow.mod, Flows, Flow#flow{pid = undefined}),
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
terminate(Reason, StateName, #state{node = NodeName, mod = Module}) ->
    lager:info(
        "Flow manager ~p (node=~p) is terminating at state ~p with reason ~p.",
        [Module, NodeName, StateName, Reason]
    ),
    ok.


%%
%%  Code upgrades.
%%
code_change(OldVsn, StateName, StateData = #state{cbm = CBModule, cbs = CBState}, Extra) ->
    {ok, NewCBState} = CBModule:code_change(OldVsn, CBState, Extra),
    {ok, StateName, StateData#state{cbs = NewCBState}}.



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
publish_attrs(#state{node = NodeName, mod = Module, flows = Flows}) ->
    FlowStatuses = [ {M, O} || #flow{mod = M, online = O} <- Flows],
    true = gproc:set_value(?REG(NodeName, Module), FlowStatuses),
    ok.


%%
%%
%%
notify_changes(ChangedFlows, StateData = #state{cbm = CBModule, cbs = CBState}) ->
    NotifyChanges = fun (#flow{mod = M, online = O}, CBS) ->
        {ok, NewCBS} = CBModule:flow_changed(M, O, CBS),
        NewCBS
    end,
    NewCBState = lists:foldr(NotifyChanges, CBState, ChangedFlows),
    {ok, StateData#state{cbs = NewCBState}}.


