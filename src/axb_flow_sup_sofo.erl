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
%%% Simple one-for-one supervisor for ESB flows.
%%%
-module(axb_flow_sup_sofo).
-compile([{parse_transform, lager_transform}]).
-behaviour(supervisor).
-export([sup_start_spec/4, start_link/4, start_flow/5]).
-export([init/1]).

-define(REF(NodeName, FlowMgrModule, FlowModule), {via, gproc, {n, l, {?MODULE, NodeName, FlowMgrModule, FlowModule}}}).


%%% ============================================================================
%%% API functions.
%%% ============================================================================

%%
%%  `Opts`
%%  :   Supervisor options, one of the following:
%%
%%      `spec`
%%      :   ...
%%      `mfa`
%%      :   ...
%%      `modules`
%%      :   ...
%%
sup_start_spec(NodeName, FlowMgrModule, FlowModule, Opts) ->
    Spec = {
        FlowModule,
        {?MODULE, start_link, [NodeName, FlowMgrModule, FlowModule, Opts]},
        permanent, brutal_kill, supervisor, [?MODULE, FlowModule]
    },
    {ok, Spec}.


%%
%%
%%
start_link(NodeName, FlowMgrModule, FlowModule, Opts) ->
    Args = {NodeName, FlowMgrModule, FlowModule, Opts},
    supervisor:start_link(?REF(NodeName, FlowMgrModule, FlowModule), ?MODULE, Args).


%%
%%  Start new flow process in this supervisor.
%%
start_flow(NodeName, FlowMgrModule, FlowModule, FlowArgs, FlowOpts) ->
    StartFun = fun (EnrichedFlowOpts) ->
        supervisor:start_child(?REF(NodeName, FlowMgrModule, FlowModule), [FlowArgs, EnrichedFlowOpts])
    end,
    axb_flow:start_sup(StartFun, FlowOpts).



%%% ============================================================================
%%% Callbacks for supervisor.
%%% ============================================================================

%%
%%  Supervisor initialization.
%%
init({NodeName, FlowMgrModule, FlowModule, Opts}) ->
    DefaultMFA = {axb_flow, start_link, [NodeName, FlowMgrModule, FlowModule]},
    DefaultMods = [axb_flow, FlowMgrModule],
    FlowMFA = proplists:get_value(mfa, Opts, DefaultMFA),
    FlowMods = proplists:get_value(modules, Opts, DefaultMods),
    DefaultSpec = {FlowModule, FlowMFA, transient, brutal_kill, worker, FlowMods},
    ChildSpec = proplists:get_value(spec, Opts, DefaultSpec),
    lager:debug(
        "Starting flow supervisor for node=~p, flow_mgr=~p, flow=~p with child_spec=~p",
        [NodeName, FlowMgrModule, FlowMgrModule, ChildSpec]
    ),
    Domain = proplists:get_value(domain, Opts, undefined),
    ok = axb_flow_mgr:register_flow(NodeName, FlowMgrModule, FlowModule, Domain, false),
    {ok, {{simple_one_for_one, 100, 1000}, [ChildSpec]}}.


