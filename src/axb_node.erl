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
-export([start_spec/2, start_link/4]).
-export([init/1, handle_sync_event/4, handle_event/3, handle_info/3, terminate/3, code_change/4]).
-export([waiting/3, starting_internal/2, starting_flows/2, starting_external/2, ready/2]).

-define(REF(NodeName), {via, gproc, {n, l, {?MODULE, NodeName}}}).


%% =============================================================================
%%  Callback definitions.
%% =============================================================================

%%
%%
%%
-callback init(Args :: term()) -> ok.


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



%% =============================================================================
%%  Internal state.
%% =============================================================================

-record(flow_sup, {
    name,
    pid
}).
-record(adapter, {
    name,
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
    case Module:init(Args) of
        {ok, AdaptersToWait, FlowSupsToWait} ->
            StateData = #state{
                name = NodeName,
                mod = Module,
                flow_sups = [ #flow_sup{name = F} || F <- FlowSupsToWait ],
                adapters  = [ #adapter {name = A} || A <- AdaptersToWait ]
            },
            to_wait_or_start(ok, StateData);
        {stop, Reason} ->
            {stop, Reason};
        ignore ->
            ignore
    end.


%%
%%
%%
waiting({register_flow_sup, Name, Pid}, From, StateData = #state{flow_sups = FlowSups}) ->
    NewFlowSup = #flow_sup{name = Name, pid = Pid},
    Register = fun (NewFlowSups) ->
        true = erlang:link(Pid),
        true = gen_fsm:reply(From, ok),
        to_wait_or_start(next_state, StateData#state{flow_sups = NewFlowSups})
    end,
    case lists:keyfind(Name, #flow_sup.name, FlowSups) of
        false ->
            Register([NewFlowSup | FlowSups]);
        NewFlowSup ->
            {reply, ok, waiting, StateData};
        #flow_sup{pid = undefined} ->
            Register(lists:keyreplace(Name, #flow_sup.name, FlowSups, NewFlowSup));
        #flow_sup{} ->
            {reply, {error, already_registered}, waiting, StateData}
    end;

waiting({register_adapter, Name, Pid}, From, StateData = #state{adapters = Adapters}) ->
    NewAdapter = #adapter{name = Name, pid = Pid},
    Register = fun (NewAdapters) ->
        true = erlang:link(Pid),
        true = gen_fsm:reply(From, ok),
        to_wait_or_start(next_state, StateData#state{adapters = NewAdapters})
    end,
    case lists:keyfind(Name, #adapter.name, Adapters) of
        false ->
            Register([NewAdapter | Adapters]);
        NewAdapter ->
            {reply, ok, waiting, StateData};
        #adapter{pid = undefined} ->
            Register(lists:keyreplace(Name, #adapter.name, Adapters, NewAdapter));
        #adapter{} ->
            {reply, {error, already_registered}, waiting, StateData}
    end.


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
%%
%%
handle_sync_event(_Request, _From, StateName, StateData) ->
    {reply, undefined, StateName, StateData}.


%%
%%
%%
handle_event(_Request, StateName, StateData) ->
    {next_state, StateName, StateData}.


%%
%%
%%
handle_info(_Request, StateName, StateData) ->
    {next_state, StateName, StateData}.


%%
%%
%%
terminate(_Reason, _StateName, _StateData) ->
    ok.


%%
%%
%%
code_change(OldVsn, StateName, StateData = #state{mod = Module}, Extra) ->
    ok = Module:code_change(OldVsn, Extra),
    {ok, StateName, StateData}.



%%% ============================================================================
%%% Helper functions.
%%% ============================================================================


%%
%%
%%
to_wait_or_start(Tag, StateData) ->
    case have_all_deps(StateData) of
        true  -> {Tag, starting_internal, StateData, 0};
        false -> {Tag, waiting, StateData}
    end.


%%
%%  Check, if we have all deps registered.
%%
have_all_deps(#state{flow_sups = FlowSups, adapters = Adapters}) ->
    FlowSupsMissing = lists:keymember(undefined, #flow_sup.pid, FlowSups),
    AdaptersMissing = lists:keymember(undefined, #adapter.pid,  Adapters),
    not (FlowSupsMissing or AdaptersMissing).


