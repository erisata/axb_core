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
%%% TODO: Add functions for managing flows (suspend, etc).
%%%
-module(axb_flow_mgr).
-behaviour(gen_fsm).
-compile([{parse_transform, lager_transform}]).
-export([start_link/6, info/2, register_flow/2, unregister_flow/2, flows_online/4]).
-export([init/1, handle_sync_event/4, handle_event/3, handle_info/3, terminate/3, code_change/4]).
-export([waiting/2, ready/2]).

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
        {ok, [FlowToWait :: module()]}.


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
start_link(Name, NodeName, Module, MgrModule, Args, Opts) ->
    gen_fsm:start_link(Name, ?MODULE, {NodeName, Module, MgrModule, Args}, Opts).


%%
%%  Get adapter's info.
%%
-spec info(
        NodeName :: atom(),
        What     :: all | flows
    ) ->
        {ok, Info :: term()}.

info(Name, What) ->
    gen_fsm:sync_send_all_state_event(Name, {info, What}).


%%
%%  Register new flow to this manager.
%%  This function must be called from the registering process.
%%
register_flow(Name, FlowModule) ->
    FlowPid = self(),
    gen_fsm:sync_send_all_state_event(Name, {register_flow, FlowModule, FlowPid}).



%%
%%  Unregister the flow from this manager.
%%
unregister_flow(Name, FlowModule) ->
    gen_fsm:sync_send_all_state_event(Name, {unregister_flow, FlowModule}).


%%
%%  Change flow status for the specific flow manager.
%%
flows_online(NodeName, FlowMgrModule, DomainsOrFlows, Online) ->
    ok. % TODO Implement mode management.



%%% ============================================================================
%%% Internal data structures.
%%% ============================================================================

%%
%%  Represents single flow type (not a flow instance).
%%
-record(flow, {
    mod     :: module(),
    pid     :: pid()
}).

%%
%%  FSM state data.
%%
-record(state, {
    node    :: atom(),
    mod     :: module(),    %% User-defined module for the flow manager (name).
    cbm     :: module(),    %% Callback module for the flow manager implementation.
    cbs     :: term(),      %% Callback state for the flow manager implementation.
    flows   :: [#flow{}]
}).



%%% ============================================================================
%%% Callbacks for `gen_fsm`.
%%% ============================================================================


%%
%%
%%
init({NodeName, Module, CBModule, Args}) ->
    erlang:process_flag(trap_exit, true),
    case CBModule:init(Args) of
        {ok, FlowsToWait, CBState} ->
            StateData = #state{
                node = NodeName,
                mod = Module,
                cbm = CBModule,
                cbs = CBState,
                flows = [ #flow{mod = F} || F <- FlowsToWait ]
            },
            case have_all_deps(StateData) of
                true  -> {ok, ready, StateData, 0};
                false -> {ok, waiting, StateData, ?WAIT_INFO_DELAY}
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
ready(timeout, StateData = #state{node = NodeName, mod = Module}) ->
    ok = axb_node:register_flow_mgr(NodeName, Module, []),
    lager:debug("Flow manager ~p is ready at node ~p.", [Module, NodeName]),
    {next_state, ready, StateData}.


handle_sync_event({register_flow, FlowModule, FlowPid}, _From, StateName, StateData) ->
    #state{flows = Flows} = StateData,
    NewFlow = #flow{mod = FlowModule, pid = FlowPid},
    Register = fun (NewFlows) ->
        true = erlang:link(FlowPid),
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
        flows = Flows
    } = StateData,
    Reply = case What of
        flows ->
            {ok, [
                {M, flow_status(F)} || F = #flow{mod = M} <- Flows
            ]}
    end,
    {reply, Reply, StateName, StateData}.


%%
%%  All-state asynchronous events.
%%
handle_event(_Request, StateName, StateData) ->
    {next_state, StateName, StateData}.


%%
%%  Other messages.
%%
handle_info({'EXIT', FromPid, Reason}, StateName, StateData) when is_pid(FromPid) ->
    #state{
        flows = Flows
    } = StateData,
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
flow_status(#flow{pid = undefined})            -> down;
flow_status(#flow{pid = Pid}) when is_pid(Pid) -> running.


