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
%%%   * Start adapters / internal services in all domains.
%%%   * Start flow manager / flows in online mode.
%%%   * Start adapters / external services in all domains.
%%%   * TODO: Start singleton processes.
%%%   * TODO: Register to the cluster. (Start the clustering? Maybe it is not the node's responsibility?)
%%%
%%% We can start the clustering so late, because it makes this node to
%%% work as a backend node. The current node can use clusteres services
%%% before starting the clustering, as any other client.
%%%
%%% TODO: The node hangs (does not register to the manager) if adapter is started that was not marked to be waited for.
%%%
-module(axb_node).
-behaviour(gen_fsm).
-compile([{parse_transform, lager_transform}]).
-export([
    start_spec/2,
    start_link/4,
    info/2,
    register_adapter/3,
    register_flow_mgr/3,
    unregister_adapter/2,
    unregister_flow_mgr/2
]).
-export([init/1, handle_sync_event/4, handle_event/3, handle_info/3, terminate/3, code_change/4]).
-export([waiting/2, starting_internal/2, starting_flows/2, starting_external/2, ready/2]).

-define(REF(NodeName), {via, gproc, {n, l, {?MODULE, NodeName}}}).
-define(WAIT_INFO_DELAY, 5000).


%%% =============================================================================
%%% Callback definitions.
%%% =============================================================================

%%
%%  This callback is invoked when starting the node.
%%  It must return a list of adapters and flow managers to wait
%%  before condidering node as started.
%%
-callback init(
        Args :: term()
    ) ->
        {ok, [AdapterToWait :: module()], [FlowMgrToWait :: term()]}.


%%
%%  This callback is invoked on code upgrades.
%%
-callback code_change(
        OldVsn :: term(),
        Extra :: term()
    ) ->
        ok.



%%% =============================================================================
%%% API functions.
%%% =============================================================================

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
        What     :: all | adapters | flow_mgrs
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
%%  Register a flow manager to this node.
%%
register_flow_mgr(NodeName, FlowMgrModule, _Opts) ->
    FlowMgrPid = self(),
    gen_fsm:sync_send_all_state_event(?REF(NodeName), {register_flow_mgr, FlowMgrModule, FlowMgrPid}).


%%
%%  Unregister an adapter from this node.
%%
unregister_adapter(NodeName, AdapterModule) ->
    gen_fsm:sync_send_all_state_event(?REF(NodeName), {unregister_adapter, AdapterModule}).


%%
%%  Unregister an adapter from this node.
%%
unregister_flow_mgr(NodeName, FlowMgrName) ->
    gen_fsm:sync_send_all_state_event(?REF(NodeName), {unregister_flow_mgr, FlowMgrName}).



%%% =============================================================================
%%% Internal state.
%%% =============================================================================

-record(flow_mgr, {
    mod,
    pid
}).

-record(adapter, {
    mod,
    pid
}).

-record(state, {
    name        :: atom(),
    mod         :: module(),
    flow_mgrs   :: [#flow_mgr{}],
    adapters    :: [#adapter{}],
    waiting_tr  :: gen_fsm:reference() | undefined  %% Waiting timer reference (if any) in order to cancel the timer before the new one is set or after waiting state is left
}).



%%% =============================================================================
%%% Callbacks for `gen_fsm`.
%%% =============================================================================

%%
%%
%%
init({NodeName, Module, Args}) ->
    erlang:process_flag(trap_exit, true),
    case Module:init(Args) of
        {ok, AdaptersToWait, FlowMgrsToWait} ->
            StateData = #state{
                name = NodeName,
                mod = Module,
                flow_mgrs  = [ #flow_mgr{mod = F} || F <- FlowMgrsToWait ],
                adapters   = [ #adapter {mod = A} || A <- AdaptersToWait ],
                waiting_tr = undefined
            },
            {next_state, NextState, NewStateData} = case have_all_deps(StateData) of
                true  -> starting_internal(enter, StateData);
                false -> waiting(enter, StateData)
            end,
            {ok, NextState, NewStateData};
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

waiting(waiting_timeout, StateData = #state{adapters = Adapters, flow_mgrs = FlowMgrs}) ->
    MissingAdapters = [ M || #adapter{mod = M,  pid = undefined} <- Adapters ],
    MissingFlowMgrs = [ N || #flow_mgr{mod = N, pid = undefined} <- FlowMgrs ],
    lager:info("Still waiting for adapters ~p and flow managers ~p", [MissingAdapters, MissingFlowMgrs]),
    waiting(enter, StateData#state{waiting_tr = undefined}).


%%
%%  The `starting_internal` state.
%%
starting_internal(enter, StateData) ->
    NewStateData = cancel_waiting_timeout(StateData),
    ok = gen_fsm:send_event(self(), start_internal),
    {next_state, starting_internal, NewStateData};

starting_internal(start_internal, StateData = #state{name = NodeName, adapters = Adapters}) ->
    lager:debug("Node ~p is starting internal services for all known adapters.", [NodeName]),
    StartAdapterInternalServices = fun (#adapter{mod = AdapterModule}) ->
        case is_adapter_startup_enabled(NodeName, AdapterModule) of
            true ->
                EnabledDomains = adapter_domains_enabled_on_startup(NodeName, AdapterModule),
                ok = axb_adapter:domain_online(NodeName, AdapterModule, EnabledDomains, internal, true);
            false ->
                lager:warning("Skipping disabled adapter ~p at ~p.", [AdapterModule, NodeName])
        end
    end,
    ok = lists:foreach(StartAdapterInternalServices, Adapters),
    starting_flows(enter, StateData).


%%
%%  The `starting_flows` state.
%%
starting_flows(enter, StateData) ->
    ok = gen_fsm:send_event(self(), start_flows),
    {next_state, starting_flows, StateData};

starting_flows(start_flows, StateData = #state{name = NodeName, flow_mgrs = FlowMgrs}) ->
    lager:debug("Node ~p is starting flow managers.", [NodeName]),
    StartFlowMgrs = fun (#flow_mgr{mod = FlowMgrModule}) ->
        ok = axb_flow_mgr:flow_online(NodeName, FlowMgrModule, all, true)
    end,
    ok = lists:foreach(StartFlowMgrs, FlowMgrs),
    starting_external(enter, StateData).


%%
%%  The `starting_external` state.
%%
starting_external(enter, StateData) ->
    ok = gen_fsm:send_event(self(), start_external),
    {next_state, starting_external, StateData};

starting_external(start_external, StateData = #state{name = NodeName, adapters = Adapters}) ->
    lager:debug("Node ~p is starting external services for all known adapters.", [NodeName]),
    StartAdapterExternalServices = fun (#adapter{mod = AdapterModule}) ->
        case is_adapter_startup_enabled(NodeName, AdapterModule) of
            true ->
                EnabledDomains = adapter_domains_enabled_on_startup(NodeName, AdapterModule),
                ok = axb_adapter:domain_online(NodeName, AdapterModule, EnabledDomains, all, true);
            false ->
                lager:warning("Skipping disabled adapter ~p at ~p.", [AdapterModule, NodeName])
        end
    end,
    ok = lists:foreach(StartAdapterExternalServices, Adapters),
    ready(enter, StateData).


%%
%%  The `ready` state.
%%
ready(enter, StateData = #state{name = NodeName}) ->
    ok = axb_node_mgr:register_node(NodeName, []),
    ok = axb_stats:node_registered(NodeName),
    ok = axb_node_events:node_state_changed(NodeName, {state, ready}),
    lager:debug("Node ~p is ready.", [NodeName]),
    {next_state, ready, StateData}.


%%
%%  All-state synchronous events.
%%
handle_sync_event({register_adapter, Module, Pid}, From, StateName, StateData) ->
    #state{adapters = Adapters} = StateData,
    NewAdapter = #adapter{mod = Module, pid = Pid},
    Register = fun (NewAdapters) ->
        true = erlang:link(Pid),
        NewStateData = StateData#state{adapters = NewAdapters},
        case StateName of
            waiting ->
                gen_fsm:reply(From, ok),
                case have_all_deps(NewStateData) of
                    true ->  starting_internal(enter, NewStateData);
                    false -> waiting(enter, NewStateData)
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

handle_sync_event({register_flow_mgr, Module, Pid}, From, StateName, StateData) ->
    #state{flow_mgrs = FlowMgrs} = StateData,
    NewFlowMgr = #flow_mgr{mod = Module, pid = Pid},
    Register = fun (NewFlowMgrs) ->
        true = erlang:link(Pid),
        NewStateData = StateData#state{flow_mgrs = NewFlowMgrs},
        case StateName of
            waiting ->
                gen_fsm:reply(From, ok),
                case have_all_deps(NewStateData) of
                    true ->  starting_internal(enter, NewStateData);
                    false -> waiting(enter, NewStateData)
                end;
            _ ->
                {reply, ok, StateName, NewStateData}
        end
    end,
    case lists:keyfind(Module, #flow_mgr.mod, FlowMgrs) of
        false ->
            Register([NewFlowMgr | FlowMgrs]);
        NewFlowMgr ->
            {reply, ok, StateName, StateData};
        #flow_mgr{pid = undefined} ->
            Register(lists:keyreplace(Module, #flow_mgr.mod, FlowMgrs, NewFlowMgr));
        #flow_mgr{} ->
            {reply, {error, already_registered}, StateName, StateData}
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

handle_sync_event({unregister_flow_mgr, Module}, _From, StateName, StateData) ->
    #state{flow_mgrs = FlowMgrs} = StateData,
    case lists:keytake(Module, #flow_mgr.mod, FlowMgrs) of
        false ->
            lager:warning("Attempt to unregister unknown flow manager ~p.", [Module]),
            {reply, ok, StateName, StateData};
        {value, #flow_mgr{pid = Pid}, NewFlowMgrs} ->
            lager:info("Unregistering flow manager ~p, pid=~p", [Module, Pid]),
            true = erlang:unlink(Pid),
            NewStateData = StateData#state{flow_mgrs = NewFlowMgrs},
            {reply, ok, StateName, NewStateData}
    end;

handle_sync_event({info, What}, _From, StateName, StateData) ->
    #state{
        mod = Mod,
        adapters = Adapters,
        flow_mgrs = FlowMgrs
    } = StateData,
    Reply = case What of
        adapters ->
            {ok, [
                {M, adapter_status(A)} || A = #adapter{mod = M} <- Adapters
            ]};
        flow_mgrs ->
            {ok, [
                {M, flow_mgr_status(F)} || F = #flow_mgr{mod = M} <- FlowMgrs
            ]};
        details ->
            {RelName, RelVersion, _RelApps, RelStatus} = case release_handler:which_releases(current) of
                [Rel] ->
                    Rel;
                [] ->
                    case release_handler:which_releases(permanent) of
                        [Rel] -> Rel;
                        []    -> {undefined, undefined, undefined, undefined}
                    end
            end,
            {AppName, AppDesc, AppVersion} = case application:get_application(Mod) of
                undefined ->
                    {undefined, undefined, undefined};
                {ok, NodeAppName} ->
                    case lists:keyfind(NodeAppName, 1, application:which_applications()) of
                        false -> {undefined, undefined, undefined};
                        App   -> App
                    end
            end,
            {UptimeMS, _} = erlang:statistics(wall_clock),
            {ok, [
                {erlang_app, [
                    {name,          AppName},
                    {description,   AppDesc},
                    {version,       AppVersion}
                ]},
                {erlang_rel, [
                    {name,      RelName},
                    {version,   RelVersion},
                    {status,    RelStatus}
                ]},
                {erlang_node, [
                    {otp_release,   erlang:system_info(otp_release)},
                    {node_name,     erlang:node()},
                    {node_uptime,   UptimeMS div 1000}
                ]},
                {adapters, [
                    {M, [
                        {status, adapter_status(A)}
                    ]}
                    || A = #adapter{mod = M} <- Adapters
                ]},
                {flow_mgrs, [
                    {M, [
                        {status, flow_mgr_status(F)}
                    ]}
                    || F = #flow_mgr{mod = M} <- FlowMgrs
                ]}
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
        flow_mgrs = FlowMgrs
    } = StateData,
    Adapter = lists:keyfind(FromPid, #adapter.pid, Adapters),
    FlowMgr = lists:keyfind(FromPid, #flow_mgr.pid, FlowMgrs),
    case {Adapter, FlowMgr} of
        {#adapter{mod = Module}, false} ->
            lager:warning("Adapter terminated, module=~p, pid=~p, reason=~p", [Module, FromPid, Reason]),
            NewAdapters = lists:keyreplace(Module, #adapter.mod, Adapters, Adapter#adapter{pid = undefined}),
            {next_state, StateName, StateData#state{adapters = NewAdapters}};
        {false, #flow_mgr{mod = Module}} ->
            lager:warning("Flow manager terminated, name=~p, pid=~p, reason=~p", [Module, FromPid, Reason]),
            NewFlowMgrs = lists:keyreplace(Module, #flow_mgr.mod, FlowMgrs, FlowMgr#flow_mgr{pid = undefined}),
            {next_state, StateName, StateData#state{flow_mgrs = NewFlowMgrs}};
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
have_all_deps(#state{flow_mgrs = FlowMgrs, adapters = Adapters}) ->
    FlowMgrsMissing = lists:keymember(undefined, #flow_mgr.pid, FlowMgrs),
    AdaptersMissing = lists:keymember(undefined, #adapter.pid,  Adapters),
    not (FlowMgrsMissing or AdaptersMissing).


%%
%%  Determine adapter's status.
%%
adapter_status(#adapter{pid = undefined})            -> down;
adapter_status(#adapter{pid = Pid}) when is_pid(Pid) -> running.


%%
%%  Determine flow_mgr's status.
%%
flow_mgr_status(#flow_mgr{pid = undefined})            -> down;
flow_mgr_status(#flow_mgr{pid = Pid}) when is_pid(Pid) -> running.


%%
%%  Returns a list of adapter domains, enabled on startup.
%%
adapter_domains_enabled_on_startup(NodeName, AdapterModule) ->
    FilterEnabledDomains = fun ({DomainName, _InternalServicesStatus, _ExternalServicesStatus}) ->
        case is_adapter_domain_startup_enabled(NodeName, AdapterModule, DomainName) of
            true  -> {true, DomainName};
            false -> false
        end
    end,
    {ok, DomainStatuses} = axb_adapter:info(NodeName, AdapterModule, domains),
    lists:filtermap(FilterEnabledDomains, DomainStatuses).


%%
%%  Checks, if the specified adapter is enabled on startup.
%%
is_adapter_startup_enabled(NodeName, AdapterModule) ->
    is_startup_enabled({NodeName, AdapterModule}).


%%
%%  Checks, if the specified adapter domain is enabled on startup.
%%
is_adapter_domain_startup_enabled(NodeName, AdapterModule, DomainName) ->
    is_startup_enabled({NodeName, AdapterModule, DomainName}).


is_startup_enabled(Key) ->
    StartupConf = axb_core_app:get_env(startup, []),
    case lists:keyfind(Key, 1, StartupConf) of
        false ->
            true;
        {Key, true} ->
            true;
        {Key, false} ->
            false;
        {Key, {node, Node}} when is_atom(Node) ->
            erlang:node() =:= Node;
        {Key, {node, Nodes}} when is_list(Nodes) ->
            lists:member(erlang:node(), Nodes);
        {key, {predicate, Module, Function, Args}} ->
            case erlang:apply(Module, Function, Args) of
                true  -> true;
                false -> false
            end
    end.


%%
%%  Cancels the waiting_timeout timer, if one is set.
%%
cancel_waiting_timeout(StateData = #state{waiting_tr = undefined}) ->
    StateData;

cancel_waiting_timeout(StateData = #state{waiting_tr = Ref}) ->
    _ = gen_fsm:cancel_timer(Ref),
    StateData#state{waiting_tr = undefined}.



