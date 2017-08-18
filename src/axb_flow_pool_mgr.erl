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
%%% The manager process for the `axb_flow_mgr`.
%%%
-module(axb_flow_pool_mgr).
-compile([{parse_transform, lager_transform}]).
-behaviour(axb_flow_mgr).
-export([start_link/4, register_flow_sup/4]).
-export([init/1, flow_changed/3, code_change/3]).


%%% ============================================================================
%%% Public API.
%%% ============================================================================

%%
%%  Start the flow manager process.
%%
start_link(NodeName, Module, Args, Opts) ->
    axb_flow_mgr:start_link(NodeName, Module, ?MODULE, {NodeName, Module, Args}, Opts).


%%
%%  Register new flow to this manager. This function can be called by
%%  any process. It starts the corresponding supervisor that must then
%%  register itself to this module by calling register_flow_sup/3.
%%
register_flow_sup(NodeName, Module, FlowModule, FlowArgs) ->
    StartFun = start_flow_sup_fun(NodeName, Module, FlowModule, FlowArgs),
    {ok, _Pid} = StartFun(),
    ok.



%%% ============================================================================
%%% Internal data structures.
%%% ============================================================================

-record(state, {
    node    :: atom(),
    mod     :: module()
}).


%%% ============================================================================
%%% Callbacks for `axb_flow_mgr'.
%%% ============================================================================

%%
%%
%%
init({NodeName, Module, Args}) ->
    case Module:init(Args) of
        {ok, FlowDomains, FlowSupSpecs} ->
            NormalizedSpecs = lists:map(fun normalize_flow_sup_spec/1, FlowSupSpecs),
            lager:debug("Node ~p flow manager ~p starting initial flows asynchronously.", [NodeName, Module]),
            _StartupPids = [ spawn_link(start_flow_sup_fun(NodeName, Module, FM, FA)) || {FM, FA} <- NormalizedSpecs ],
            InitialFlows = [ M || {M, _A} <- NormalizedSpecs ],
            State = #state{node = NodeName, mod = Module},
            {ok, FlowDomains, InitialFlows, State};
        {stop, Reason} ->
            {stop, Reason}
    end.


%%
%%
%%
flow_changed(FlowModule, Online, State = #state{node = NodeName, mod = Module}) ->
    lager:info("Flow ~p status changed to online=~p in ~p:~p", [Module, Online, FlowModule, NodeName]),
    {ok, State}.


%%
%%
%%
code_change(OldVsn, State = #state{mod = Module}, Extra) ->
    ok = Module:code_change(OldVsn, Extra),
    {ok, State}.



%%% ============================================================================
%%% Internal functions.
%%% ============================================================================

%%
%%
%%
normalize_flow_sup_spec({FlowModule, FlowArgs}) when is_atom(FlowModule) -> {FlowModule, FlowArgs};
normalize_flow_sup_spec(FlowModule)             when is_atom(FlowModule) -> {FlowModule, undefined}.


%%
%%
%%
start_flow_sup_fun(NodeName, Module, FlowModule, FlowArgs) ->
    case axb_flow_supervised:sup_start_spec(FlowModule, FlowArgs) of
        {ok, SupStartSpec} ->
            fun () ->
                {ok, _Pid} = axb_flow_pool_sup:add_flow_sup(NodeName, Module, FlowModule, SupStartSpec)
            end;
        {error, Reason} ->
            {error, Reason}
    end.


