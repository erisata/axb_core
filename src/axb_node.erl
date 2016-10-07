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
    register_adapter/4,
    register_flow_mgr/4,
    unregister_adapter/2,
    unregister_flow_mgr/2
]).
-export([init/1, handle_sync_event/4, handle_event/3, handle_info/3, terminate/3, code_change/4]).
-export([waiting/2, starting_internal/2, starting_flows/2, starting_external/2, ready/2]).
-include("axb.hrl").

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
        Args    :: term()
    ) ->
        {ok, [AdapterToWait :: axb_adapter()], [FlowMgrToWait :: axb_flow_mgr()]}.


%%
%%  This callback is invoked on code upgrades.
%%
-callback code_change(
        OldVsn  :: term(),
        Extra   :: term()
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
        1000,
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
-spec register_adapter(
        NodeName    :: axb_node(),
        AdapterName :: axb_adapter(),
        DomainNames :: [axb_domain()],
        Opts        :: list()
    ) ->
        {ok, [{DomainName :: axb_adapter(), Internal :: boolean(), External :: boolean()}]} |
        {error, Reason :: term()}.

register_adapter(NodeName, AdapterName, DomainNames, _Opts) ->
    AdapterPid = self(),
    gen_fsm:sync_send_all_state_event(?REF(NodeName), {register_adapter, AdapterName, AdapterPid, DomainNames}).


%%
%%  Register a flow manager to this node.
%%
-spec register_flow_mgr(
        NodeName    :: axb_node(),
        FlowMgrName :: axb_flow_mgr(),
        FlowNames   :: [axb_flow()],
        Opts        :: list()
    ) ->
        {ok, [{FlowName :: axb_flow(), Online :: boolean()}]} |
        {error, Reason :: term()}.

register_flow_mgr(NodeName, FlowMgrName, FlowNames, _Opts) ->
    FlowMgrPid = self(),
    gen_fsm:sync_send_all_state_event(?REF(NodeName), {register_flow_mgr, FlowMgrName, FlowMgrPid, FlowNames}).


%%
%%  Unregister an adapter from this node.
%%
unregister_adapter(NodeName, AdapterName) ->
    gen_fsm:sync_send_all_state_event(?REF(NodeName), {unregister_adapter, AdapterName}).


%%
%%  Unregister an adapter from this node.
%%
unregister_flow_mgr(NodeName, FlowMgrName) ->
    gen_fsm:sync_send_all_state_event(?REF(NodeName), {unregister_flow_mgr, FlowMgrName}).



%%% =============================================================================
%%% Internal state.
%%% =============================================================================

%%
%%  Manual domain state changes are not reflected here, therefore the
%%  adapter will return to the predefined state, if the adapter will
%%  be restarted (e.g. after a crash).
%%
-record(adapter, {
    name    :: axb_adapter(),
    pid     :: pid(),
    domains :: [{DomainName :: axb_domain(), Internal :: boolean(), External :: boolean()}]
}).


%%
%%  Manual flow state changes are not reflected here.
%%  See #adapter{} for more details.
%%
-record(flow_mgr, {
    name    :: axb_flow_mgr(),
    pid     :: pid(),
    flows   :: [{FlowName :: axb_flow(), Online :: boolean()}]
}).


-record(state, {
    name        :: atom(),
    cb_mod      :: module(),
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
init({NodeName, CBModule, Args}) ->
    erlang:process_flag(trap_exit, true),
    case CBModule:init(Args) of
        {ok, AdaptersToWait, FlowMgrsToWait} ->
            StateData = #state{
                name       = NodeName,
                cb_mod     = CBModule,
                flow_mgrs  = [ #flow_mgr{name = FM, flows = []} || FM <- FlowMgrsToWait ],
                adapters   = [ #adapter{name = A, domains = []} || A <- AdaptersToWait ],
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
    MissingAdapters = [ N || #adapter{name = N, pid = undefined} <- Adapters ],
    MissingFlowMgrs = [ N || #flow_mgr{name = N, pid = undefined} <- FlowMgrs ],
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
    StartAdapterInternalServices = fun (Adapter = #adapter{name = AdapterName, domains = Domains}) ->
        case is_adapter_startup_enabled(NodeName, AdapterName) of
            true ->
                EnabledDomains = adapter_domains_enabled_on_startup(NodeName, AdapterName, Domains),
                ok = axb_adapter:domain_online(NodeName, AdapterName, EnabledDomains, internal, true),
                UpdateDomains = fun ({D, _I, E}) ->
                    {D, lists:member(D, EnabledDomains), E}
                end,
                Adapter#adapter{domains = lists:map(UpdateDomains, Domains)};
            false ->
                lager:warning("Skipping disabled adapter ~p at ~p.", [AdapterName, NodeName]),
                Adapter
        end
    end,
    NewAdapters = lists:map(StartAdapterInternalServices, Adapters),
    NewStateData = StateData#state{adapters = NewAdapters},
    starting_flows(enter, NewStateData).


%%
%%  The `starting_flows` state.
%%
starting_flows(enter, StateData) ->
    ok = gen_fsm:send_event(self(), start_flows),
    {next_state, starting_flows, StateData};

starting_flows(start_flows, StateData = #state{name = NodeName, flow_mgrs = FlowMgrs}) ->
    lager:debug("Node ~p is starting flow managers.", [NodeName]),
    StartFlowMgrs = fun (#flow_mgr{name = FlowMgrName}) ->
        ok = axb_flow_mgr:flow_online(NodeName, FlowMgrName, all, true)
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
    StartAdapterExternalServices = fun (Adapter = #adapter{name = AdapterName, domains = Domains}) ->
        case is_adapter_startup_enabled(NodeName, AdapterName) of
            true ->
                EnabledDomains = adapter_domains_enabled_on_startup(NodeName, AdapterName, Domains),
                ok = axb_adapter:domain_online(NodeName, AdapterName, EnabledDomains, external, true),
                UpdateDomains = fun ({D, I, _E}) ->
                    {D, I, lists:member(D, EnabledDomains)}
                end,
                Adapter#adapter{domains = lists:map(UpdateDomains, Domains)};
            false ->
                lager:warning("Skipping disabled adapter ~p at ~p.", [AdapterName, NodeName]),
                Adapter
        end
    end,
    NewAdapters = lists:map(StartAdapterExternalServices, Adapters),
    NewStateData = StateData#state{adapters = NewAdapters},
    ready(enter, NewStateData).


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
handle_sync_event({register_adapter, AdapterName, AdapterPid, DomainNames}, From, StateName, StateData) ->
    #state{
        name     = NodeName,
        adapters = Adapters
    } = StateData,
    Register = fun (NewAdapters, NewDomains) ->
        lager:debug("Adapter registered, name=~p, pid=~p", [AdapterName, AdapterPid]),
        true = erlang:link(AdapterPid),
        NewStateData = StateData#state{adapters = NewAdapters},
        case StateName of
            waiting ->
                gen_fsm:reply(From, {ok, NewDomains}),
                case have_all_deps(NewStateData) of
                    true ->  starting_internal(enter, NewStateData);
                    false -> waiting(enter, NewStateData)
                end;
            _ ->
                {reply, {ok, NewDomains}, StateName, NewStateData}
        end
    end,
    case lists:keyfind(AdapterName, #adapter.name, Adapters) of
        false ->
            % New adapter registered.
            NewDomains = adapter_domain_statuses(NodeName, AdapterName, DomainNames, []),
            NewAdapter = #adapter{
                name    = AdapterName,
                pid     = AdapterPid,
                domains = NewDomains
            },
            Register([NewAdapter | Adapters], NewDomains);
        #adapter{pid = AdapterPid, domains = OldDomains} = OldAdapter ->
            % Existing adapter re-registered with the same PID, do almost nothing.
            NewDomains = adapter_domain_statuses(NodeName, AdapterName, DomainNames, OldDomains),
            NewAdapter = OldAdapter#adapter{
                domains = NewDomains
            },
            NewStateData = StateData#state{
                adapters = lists:keyreplace(AdapterName, #adapter.name, Adapters, NewAdapter)
            },
            {reply, {ok, NewDomains}, NewStateData, StateData};
        #adapter{pid = undefined, domains = OldDomains} = OldAdapter ->
            % New adapter registered, or re-registered after a crash.
            NewDomains = adapter_domain_statuses(NodeName, AdapterName, DomainNames, OldDomains),
            NewAdapter = OldAdapter#adapter{
                pid     = AdapterPid,
                domains = NewDomains
            },
            Register(lists:keyreplace(AdapterName, #adapter.name, Adapters, NewAdapter), NewDomains);
        #adapter{pid = OldAdapterPid} when OldAdapterPid =/= AdapterPid ->
            % Adapter is already registered with another PID.
            {reply, {error, already_registered}, StateName, StateData}
    end;

handle_sync_event({register_flow_mgr, FlowMgrName, FlowMgrPid, FlowNames}, From, StateName, StateData) ->
    #state{
        name      = NodeName,
        flow_mgrs = FlowMgrs
    } = StateData,
    Register = fun (NewFlowMgrs, NewFlows) ->
        lager:debug("FlowMgr registered, name=~p, pid=~p", [FlowMgrName, FlowMgrPid]),
        true = erlang:link(FlowMgrPid),
        NewStateData = StateData#state{flow_mgrs = NewFlowMgrs},
        case StateName of
            waiting ->
                gen_fsm:reply(From, {ok, NewFlows}),
                case have_all_deps(NewStateData) of
                    true  -> starting_internal(enter, NewStateData);
                    false -> waiting(enter, NewStateData)
                end;
            _ ->
                {reply, {ok, NewFlows}, StateName, NewStateData}
        end
    end,
    case lists:keyfind(FlowMgrName, #flow_mgr.name, FlowMgrs) of
        false ->
            % New FlowMgr registered.
            NewFlows = flow_mgr_flow_statuses(NodeName, FlowMgrName, FlowNames, []),
            NewFlowMgr = #flow_mgr{
                name = FlowMgrName,
                pid  = FlowMgrPid
            },
            Register([NewFlowMgr | FlowMgrs], NewFlows);
        #flow_mgr{pid = FlowMgrPid, flows = OldFlows} = OldFlowMgr ->
            % Existing FlowMgr re-registered with the same PID, do almost nothing.
            NewFlows = flow_mgr_flow_statuses(NodeName, FlowMgrName, FlowNames, OldFlows),
            NewFlowMgr = OldFlowMgr#flow_mgr{
                flows = NewFlows
            },
            NewStateData = StateData#state{
                flow_mgrs = lists:keyreplace(FlowMgrName, #flow_mgr.name, FlowMgrs, NewFlowMgr)
            },
            {reply, ok, StateName, NewStateData};
        #flow_mgr{pid = undefined, flows = OldFlows} = OldFlowMgr ->
            % New FlowMgr registered, or re-registered after a crash.
            NewFlows = flow_mgr_flow_statuses(NodeName, FlowMgrName, FlowNames, OldFlows),
            NewFlowMgr = OldFlowMgr#flow_mgr{
                pid   = FlowMgrPid,
                flows = NewFlows
            },
            Register(lists:keyreplace(FlowMgrName, #flow_mgr.name, FlowMgrs, NewFlowMgr), NewFlows);
        #flow_mgr{pid = OldFlowMgrPid} when OldFlowMgrPid =/= FlowMgrPid ->
            % FlowMgr is already registered with another PID.
            {reply, {error, already_registered}, StateName, StateData}
    end;

handle_sync_event({unregister_adapter, AdapterName}, _From, StateName, StateData) ->
    #state{adapters = Adapters} = StateData,
    case lists:keytake(AdapterName, #adapter.name, Adapters) of
        false ->
            lager:warning("Attempt to unregister unknown adapter ~p.", [AdapterName]),
            {reply, ok, StateName, StateData};
        {value, #adapter{pid = Pid}, NewAdapters} ->
            lager:info("Unregistering adapter ~p, pid=~p", [AdapterName, Pid]),
            true = erlang:unlink(Pid),
            NewStateData = StateData#state{adapters = NewAdapters},
            {reply, ok, StateName, NewStateData}
    end;

handle_sync_event({unregister_flow_mgr, FlowMgrName}, _From, StateName, StateData) ->
    #state{flow_mgrs = FlowMgrs} = StateData,
    case lists:keytake(FlowMgrName, #flow_mgr.name, FlowMgrs) of
        false ->
            lager:warning("Attempt to unregister unknown flow manager ~p.", [FlowMgrName]),
            {reply, ok, StateName, StateData};
        {value, #flow_mgr{pid = Pid}, NewFlowMgrs} ->
            lager:info("Unregistering flow manager ~p, pid=~p", [FlowMgrName, Pid]),
            true = erlang:unlink(Pid),
            NewStateData = StateData#state{flow_mgrs = NewFlowMgrs},
            {reply, ok, StateName, NewStateData}
    end;

handle_sync_event({info, What}, _From, StateName, StateData) ->
    #state{
        cb_mod = CBModule,
        adapters = Adapters,
        flow_mgrs = FlowMgrs
    } = StateData,
    Reply = case What of
        adapters ->
            {ok, [
                {N, adapter_status(A)}
                || A = #adapter{name = N} <- Adapters
            ]};
        flow_mgrs ->
            {ok, [
                {N, flow_mgr_status(FM)}
                || FM = #flow_mgr{name = N} <- FlowMgrs
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
            {AppName, AppDesc, AppVersion} = case application:get_application(CBModule) of
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
                    {N, [
                        {status, adapter_status(A)}
                    ]}
                    || A = #adapter{name = N} <- Adapters
                ]},
                {flow_mgrs, [
                    {N, [
                        {status, flow_mgr_status(FM)}
                    ]}
                    || FM = #flow_mgr{name = N} <- FlowMgrs
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
        {#adapter{name = AdapterName}, false} ->
            lager:warning("Adapter terminated, name=~p, pid=~p, reason=~p", [AdapterName, FromPid, Reason]),
            NewAdapters = lists:keyreplace(AdapterName, #adapter.name, Adapters, Adapter#adapter{pid = undefined}),
            {next_state, StateName, StateData#state{adapters = NewAdapters}};
        {false, #flow_mgr{name = FlowMgrName}} ->
            lager:warning("Flow manager terminated, name=~p, pid=~p, reason=~p", [FlowMgrName, FromPid, Reason]),
            NewFlowMgrs = lists:keyreplace(FlowMgrName, #flow_mgr.name, FlowMgrs, FlowMgr#flow_mgr{pid = undefined}),
            {next_state, StateName, StateData#state{flow_mgrs = NewFlowMgrs}};
        {false, false} ->
            lager:warning("Linked process ~p terminated, exiting with reason ~p.", [FromPid, Reason]),
            {stop, Reason, StateData}
    end;

handle_info(Unknown, StateName, StateData) ->
    lager:debug("Unknown info event dropped: ~p", [Unknown]),
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
code_change(OldVsn, StateName, StateData = #state{cb_mod = CBModule}, Extra) ->
    ok = CBModule:code_change(OldVsn, Extra),
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
%%  Determine current domain statuses.
%%
adapter_domain_statuses(NodeName, AdapterName, DomainNames, KnownDomains) ->
    DomainStatus = fun (DomainName) ->
        case lists:keyfind(DomainName, 1, KnownDomains) of
            false ->
                Enabled = is_adapter_domain_startup_enabled(NodeName, AdapterName, DomainName),
                {DomainName, Enabled, Enabled};
            {DomainName, Internal, External} ->
                {DomainName, Internal, External}
        end
    end,
    lists:map(DomainStatus, DomainNames).


%%
%%  Returns a list of adapter domains, enabled on startup.
%%
adapter_domains_enabled_on_startup(NodeName, AdapterName, Domains) ->
    FilterEnabledDomains = fun ({DomainName, _Internal, _External}) ->
        case is_adapter_domain_startup_enabled(NodeName, AdapterName, DomainName) of
            true  -> {true, DomainName};
            false -> false
        end
    end,
    lists:filtermap(FilterEnabledDomains, Domains).


%%
%%  Checks, if the specified adapter is enabled on startup.
%%
is_adapter_startup_enabled(NodeName, AdapterName) ->
    is_startup_enabled({NodeName, AdapterName}).


%%
%%  Checks, if the specified adapter domain is enabled on startup.
%%
is_adapter_domain_startup_enabled(NodeName, AdapterName, DomainName) ->
    is_startup_enabled({NodeName, AdapterName, DomainName}).


%%
%%  Determine current flow statuses.
%%
flow_mgr_flow_statuses(NodeName, FlowMgrName, FlowNames, KnownFlows) ->
    FlowStatus = fun (FlowName) ->
        case lists:keyfind(FlowName, 1, KnownFlows) of
            false ->
                Enabled = is_flow_mgr_flow_startup_enabled(NodeName, FlowMgrName, FlowName),
                {FlowName, Enabled};
            {FlowName, Online} ->
                {FlowName, Online}
        end
    end,
    lists:map(FlowStatus, FlowNames).


%%
%%  Checks, if the specified FlowMgr Flow is enabled on startup.
%%
is_flow_mgr_flow_startup_enabled(NodeName, FlowMgrName, FlowName) ->
    is_startup_enabled({NodeName, FlowMgrName, FlowName}).


%%
%%
%%
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


