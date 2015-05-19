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
-behaviour(gen_server). % TODO: Gen FSM
-export([start_spec/2, start_link/5, flow_sup/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-define(REF(NodeName), {via, gproc, {n, l, {?MODULE, NodeName}}}).
-define(NODE_FLOW_SUP(NodeName), {n, l, {?MODULE, NodeName, flow_sup}}).


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
%%
%%
start_link(NodeName, NodeFlowSup, Module, Args, Opts) ->
    gen_server:start_link(?REF(NodeName), ?MODULE, {NodeName, NodeFlowSup, Module, Args}, Opts).


%%
%%  Get flow supervisor module for the specified node.
%%
flow_sup(NodeName) ->
    {ok, gproc:lookup_value(?NODE_FLOW_SUP(NodeName))}.



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
    mod         :: module(),
    flow_sups   :: [#flow_sup{}],
    adapters    :: [#adapter{}]
}).


%% =============================================================================
%%  Callbacks for `gen_server`.
%% =============================================================================

%%
%%
%%
init({NodeName, NodeFlowSup, Module, Args}) ->
    true = gproc:reg(?NODE_FLOW_SUP(NodeName), NodeFlowSup),
    ok = Module:init(Args),
    State = #state{mod = Module},
    {ok, State}.


%%
%%
%%
handle_call(_Request, _From, State) ->
    {reply, undefined, State}.


%%
%%
%%
handle_cast(_Request, State) ->
    {noreply, State}.


%%
%%
%%
handle_info(_Request, State) ->
    {noreply, State}.


%%
%%
%%
terminate(_Reason, _State) ->
    ok.


%%
%%
%%
code_change(OldVsn, State = #state{mod = Module}, Extra) ->
    ok = Module:code_change(OldVsn, Extra),
    {ok, State}.


