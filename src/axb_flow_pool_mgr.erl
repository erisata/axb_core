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
%%% TODO: Implement flow monitor (in other process/module?).
%%%      It will report flow crashes, maybe will perform
%%%      restart back-pressure and suspending of flows.
%%%
-module(axb_flow_pool_mgr).
-compile([{parse_transform, lager_transform}]).
-behaviour(axb_flow_mgr).
-export([start_link/4, register_flow_sup/4, register_flow/3, unregister_flow/3]).
-export([init/1, code_change/3]).

-define(REF(NodeName, Module), {via, gproc, {n, l, {?MODULE, NodeName, Module}}}).


%%% ============================================================================
%%% Public API.
%%% ============================================================================

%%
%%  Start the flow manager process.
%%
start_link(NodeName, Module, Args, Opts) ->
    axb_flow_mgr:start_link(?REF(NodeName, Module), NodeName, Module, ?MODULE, {NodeName, Module, Args}, Opts).


%%
%%  Register new flow to this manager. This function can be called by
%%  any process. It starts the corresponding supervisor that must then
%%  register itself to this module by calling register_flow_sup/3.
%%
register_flow_sup(NodeName, Module, FlowModule, FlowArgs) ->
    StartFun = start_flow_sup_fun(NodeName, Module, FlowModule, FlowArgs),
    {ok, _Pid} = StartFun(),
    ok.


%%
%%  Register new flow to this manager.
%%  This function must be called from the registering process.
%%
register_flow(NodeName, Module, FlowModule) ->
    axb_flow_mgr:register_flow(?REF(NodeName, Module), FlowModule).


%%
%%  Unregister the flow from this manager.
%%
unregister_flow(NodeName, Module, FlowModule) ->
    axb_flow_mgr:unregister_flow(?REF(NodeName, Module), FlowModule).



%%% ============================================================================
%%% Internal data structures.
%%% ============================================================================

-record(state, {
    node    :: atom(),
    mod     :: module()
}).


%%% ============================================================================
%%% Callbacks for `axb_flow_mgr`.
%%% ============================================================================

%%
%%
%%
init({NodeName, Module, Args}) ->
    case Module:init(Args) of
        {ok, FlowSupSpecs} ->
            NormalizedSpecs = lists:map(fun normalize_flow_sup_spec/1, FlowSupSpecs),
            lager:debug("Node ~p flow manager ~p starting initial flows asynchronously.", [NodeName, Module]),
            _StartupPids = [ spawn_link(start_flow_sup_fun(NodeName, Module, FM, FA)) || {FM, FA} <- NormalizedSpecs ],
            InitialFlows = [ M || {M, _A} <- NormalizedSpecs ],
            State = #state{node = NodeName, mod = Module},
            {ok, InitialFlows, State};
        {stop, Reason} ->
            {stop, Reason}
    end.


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


