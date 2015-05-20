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
%%%
%%% Startup procedure:
%%%
%%%   * Start node.
%%%   * Start adapters / internal services.
%%%   * Start flow supervisor / flows (in offline mode?).
%%%   * Start adapters / external services.
%%%   * (Take flows to the online mode?).
%%%   * Start processes.
%%%   * Register to the cluster. (Start the clustering? Maybe it is not the node's responsibility?)
%%%
%%% We can start the clustering so late, because it makes this node to
%%% work as a backend node. The current node can use clusteres services
%%% before starting the clustering, as any other client.
%%%
-module(axb_node).
-behaviour(gen_fsm).
-compile([{parse_transform, lager_transform}]).
-export([
    start_spec/2,
    start_link/4,
    info/2,
    register_adapter/3,
    register_flow_sup/3,
    unregister_adapter/2,
    unregister_flow_sup/2
]).
-export([init/1, handle_sync_event/4, handle_event/3, handle_info/3, terminate/3, code_change/4]).
-export([waiting/2, starting_internal/2, starting_flows/2, starting_external/2, ready/2]).

-define(REF(NodeName), {via, gproc, {n, l, {?MODULE, NodeName}}}).
-define(WAIT_INFO_DELAY, 5000).

%% =============================================================================
%%  Callback definitions.
%% =============================================================================

%%
%%
%%
-callback init(Args :: term()) -> {ok, [AdapterToWait :: module()], [FlowSupToWait :: term()]}.


%%
%%
%%
-callback code_change(OldVsn :: term(), Extra :: term()) -> ok.



%% =============================================================================
%% API functions.
%% =============================================================================

%%
%%  Create Supervisor's child spec for starting this node.
%%
start_spec(SpecId, {Module, Function, Args}) when is_atom(Module), is_atom(Function), is_list(Args) ->
    {SpecId,
        {Module, Function, Args},
        permanent,
        brutal_kill,
        supervisor,
        [?MODULE, Module]
    }.


%%
%%  Start this node.
%%
start_link(NodeName, Module, Args, Opts) ->
    gen_fsm:start_link(?REF(NodeName), ?MODULE, {NodeName, Module, Args}, Opts).


%%
%%  Get adapter's info.
%%
-spec info(
        NodeName :: atom(),
        What     :: all | adapters | flow_sups
    ) ->
        {ok, Info :: term()}.

info(NodeName, What) ->
    gen_fsm:sync_send_all_state_event(?REF(NodeName), {info, What}).


%%
%%  Register an adapter to this node.
%%
register_adapter(NodeName, AdapterModule, _Opts) ->
    AdapterPid = self(),
    gen_fsm:sync_send_all_state_event(?REF(NodeName), {register_adapter, AdapterModule, AdapterPid}).


%%
%%  Register a flow supervisor to this node.
%%
register_flow_sup(NodeName, FlowSupModule, _Opts) ->
    FlowSupPid = self(),
    gen_fsm:sync_send_all_state_event(?REF(NodeName), {register_flow_sup, FlowSupModule, FlowSupPid}).


%%
%%  Unregister an adapter from this node.
%%
unregister_adapter(NodeName, AdapterModule) ->
    gen_fsm:sync_send_all_state_event(?REF(NodeName), {unregister_adapter, AdapterModule}).


%%
%%  Unregister an adapter from this node.
%%
unregister_flow_sup(NodeName, FlowSupName) ->
    gen_fsm:sync_send_all_state_event(?REF(NodeName), {unregister_flow_sup, FlowSupName}).



%% =============================================================================
%%  Internal state.
%% =============================================================================

-record(flow_sup, {
    name,
    pid
}).
-record(adapter, {
    mod,
    pid
}).
-record(state, {
    name        :: atom(),
    mod         :: module(),
    flow_sups   :: [#flow_sup{}],
    adapters    :: [#adapter{}]
}).


%% =============================================================================
%%  Callbacks for `gen_fsm`.
%% =============================================================================

%%
%%
%%
init({NodeName, Module, Args}) ->
    erlang:process_flag(trap_exit, true),
    case Module:init(Args) of
        {ok, AdaptersToWait, FlowSupsToWait} ->
            StateData = #state{
                name = NodeName,
                mod = Module,
                flow_sups = [ #flow_sup{name = F} || F <- FlowSupsToWait ],
                adapters  = [ #adapter {mod = A} || A <- AdaptersToWait ]
            },
            case have_all_deps(StateData) of
                true  -> {ok, starting_internal, StateData, 0};
                false -> {ok, waiting, StateData, ?WAIT_INFO_DELAY}
            end;
        {stop, Reason} ->
            {stop, Reason};
        ignore ->
            ignore
    end.



waiting(timeout, StateData = #state{adapters = Adapters, flow_sups = FlowSups}) ->
    MissingAdapters = [ M || #adapter{mod = M, pid = undefined} <- Adapters ],
    MissingFlowSups = [ N || #flow_sup{name = N, pid = undefined} <- FlowSups ],
    lager:info("Still waiting for adapters ~p and flow supervisors ~p", [MissingAdapters, MissingFlowSups]),
    {next_state, waiting, StateData, ?WAIT_INFO_DELAY}.


%%
%% TODO: Registrations can be performed during and after startup.
%%
starting_internal(timeout, StateData) ->
    {next_state, starting_flows, StateData, 0}.


starting_flows(timeout, StateData) ->
    {next_state, starting_external, StateData, 0}.


starting_external(timeout, StateData) ->
    {next_state, ready, StateData, 0}.


ready(timeout, StateData = #state{name = Name}) ->
    ok = axb_node_mgr:register_node(Name, []),
    {next_state, ready, StateData}.


%%
%%  All-state synchronous events.
%%
handle_sync_event({register_adapter, Module, Pid}, _From, StateName, StateData) ->
    #state{adapters = Adapters} = StateData,
    NewAdapter = #adapter{mod = Module, pid = Pid},
    Register = fun (NewAdapters) ->
        true = erlang:link(Pid),
        NewStateData = StateData#state{adapters = NewAdapters},
        case StateName of
            waiting ->
                case have_all_deps(NewStateData) of
                    true ->  {reply, ok, starting_internal, NewStateData, 0};
                    false -> {reply, ok, waiting, NewStateData, ?WAIT_INFO_DELAY}
                end;
            _ ->
                {reply, ok, StateName, NewStateData}
        end
    end,
    case lists:keyfind(Module, #adapter.mod, Adapters) of
        false ->
            Register([NewAdapter | Adapters]);
        NewAdapter ->
            {reply, ok, StateName, StateData};
        #adapter{pid = undefined} ->
            Register(lists:keyreplace(Module, #adapter.mod, Adapters, NewAdapter));
        #adapter{} ->
            {reply, {error, already_registered}, StateName, StateData}
    end;

handle_sync_event({register_flow_sup, Name, Pid}, _From, StateName, StateData) ->
    #state{flow_sups = FlowSups} = StateData,
    NewFlowSup = #flow_sup{name = Name, pid = Pid},
    Register = fun (NewFlowSups) ->
        true = erlang:link(Pid),
        NewStateData = StateData#state{flow_sups = NewFlowSups},
        case StateName of
            waiting ->
                case have_all_deps(NewStateData) of
                    true ->  {reply, ok, starting_internal, NewStateData, 0};
                    false -> {reply, ok, waiting, NewStateData, ?WAIT_INFO_DELAY}
                end;
            _ ->
                {reply, ok, StateName, NewStateData}
        end
    end,
    case lists:keyfind(Name, #flow_sup.name, FlowSups) of
        false ->
            Register([NewFlowSup | FlowSups]);
        NewFlowSup ->
            {reply, ok, waiting, StateData, ?WAIT_INFO_DELAY};
        #flow_sup{pid = undefined} ->
            Register(lists:keyreplace(Name, #flow_sup.name, FlowSups, NewFlowSup));
        #flow_sup{} ->
            {reply, {error, already_registered}, waiting, StateData, ?WAIT_INFO_DELAY}
    end;

handle_sync_event({unregister_adapter, Module}, _From, StateName, StateData) ->
    #state{adapters = Adapters} = StateData,
    case lists:keytake(Module, #adapter.mod, Adapters) of
        false ->
            lager:warning("Attempt to unregister unknown adapter ~p.", [Module]),
            {reply, ok, StateName, StateData};
        {value, #adapter{pid = Pid}, NewAdapters} ->
            lager:info("Unregistering adapter ~p, pid=~p", [Module, Pid]),
            true = erlang:unlink(Pid),
            NewStateData = StateData#state{adapters = NewAdapters},
            {reply, ok, StateName, NewStateData}
    end;

handle_sync_event({unregister_flow_sup, Name}, _From, StateName, StateData) ->
    #state{flow_sups = FlowSups} = StateData,
    case lists:keytake(Name, #flow_sup.name, FlowSups) of
        false ->
            lager:warning("Attempt to unregister unknown flow supervisor ~p.", [Name]),
            {reply, ok, StateName, StateData};
        {value, #flow_sup{pid = Pid}, NewFlowSups} ->
            lager:info("Unregistering flow supervisor ~p, pid=~p", [Name, Pid]),
            true = erlang:unlink(Pid),
            NewStateData = StateData#state{flow_sups = NewFlowSups},
            {reply, ok, StateName, NewStateData}
    end;

handle_sync_event({info, What}, _From, StateName, StateData) ->
    #state{
        adapters = Adapters,
        flow_sups = FlowSups
    } = StateData,
    Reply = case What of
        adapters ->
            {ok, [
                {M, adapter_status(A)} || A = #adapter{mod = M} <- Adapters
            ]};
        flow_sups ->
            {ok, [
                {N, flow_sup_status(F)} || F = #flow_sup{name = N} <- FlowSups
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
        adapters  = Adapters,
        flow_sups = FlowSups
    } = StateData,
    Adapter = lists:keyfind(FromPid, #adapter.pid, Adapters),
    FlowSup = lists:keyfind(FromPid, #flow_sup.pid, FlowSups),
    case {Adapter, FlowSup} of
        {#adapter{mod = Mod}, false} ->
            lager:warning("Adapter was down, module=~p, pid=~p, reason=~p", [Mod, FromPid, Reason]),
            NewAdapters = lists:keyreplace(Mod, #adapter.mod, Adapters, Adapter#adapter{pid = undefined}),
            {next_state, StateName, StateData#state{adapters = NewAdapters}};
        {false, #flow_sup{name = Name}} ->
            lager:warning("Flow supervisor was down, name=~p, pid=~p, reason=~p", [Name, FromPid, Reason]),
            NewFlowSups = lists:keyreplace(Name, #flow_sup.name, FlowSups, FlowSup#flow_sup{pid = undefined}),
            {next_state, StateName, StateData#state{flow_sups = NewFlowSups}};
        {false, false} ->
            lager:warning("Linked process ~p terminated, exiting with reason ~p.", [FromPid, Reason]),
            {stop, Reason, StateData}
    end;

handle_info(_Request, StateName, StateData) ->
    {next_state, StateName, StateData}.


%%
%%  Termination.
%%
terminate(Reason, StateName, #state{name = Name}) ->
    lager:info("Node ~p is terminating at state ~p with reason ~p.", [Name, StateName, Reason]),
    ok.


%%
%%  Code upgrades.
%%
code_change(OldVsn, StateName, StateData = #state{mod = Module}, Extra) ->
    ok = Module:code_change(OldVsn, Extra),
    {ok, StateName, StateData}.



%%% ============================================================================
%%% Helper functions.
%%% ============================================================================



%%
%%  Check, if we have all deps registered.
%%
have_all_deps(#state{flow_sups = FlowSups, adapters = Adapters}) ->
    FlowSupsMissing = lists:keymember(undefined, #flow_sup.pid, FlowSups),
    AdaptersMissing = lists:keymember(undefined, #adapter.pid,  Adapters),
    not (FlowSupsMissing or AdaptersMissing).


%%
%%  Determine adapter's status.
%%
adapter_status(#adapter{pid = undefined})            -> down;
adapter_status(#adapter{pid = Pid}) when is_pid(Pid) -> running.


%%
%%  Determine flow_sup's status.
%%
flow_sup_status(#flow_sup{pid = undefined})            -> down;
flow_sup_status(#flow_sup{pid = Pid}) when is_pid(Pid) -> running.


