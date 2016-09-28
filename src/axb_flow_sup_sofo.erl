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
-export([sup_start_spec/5, start_link/5, start_flow/5, start_sync_flow/5]).
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
sup_start_spec(NodeName, FlowMgrModule, FlowDomain, FlowModule, Opts) ->
    Spec = {
        FlowModule,
        {?MODULE, start_link, [NodeName, FlowMgrModule, FlowDomain, FlowModule, Opts]},
        permanent, 1000, supervisor, [?MODULE, FlowModule]
    },
    {ok, Spec}.


%%
%%
%%
start_link(NodeName, FlowMgrModule, FlowDomain, FlowModule, Opts) ->
    Args = {NodeName, FlowMgrModule, FlowDomain, FlowModule, Opts},
    supervisor:start_link(?REF(NodeName, FlowMgrModule, FlowModule), ?MODULE, Args).


%%
%%  Start new flow process in this supervisor.
%%
start_flow(NodeName, FlowMgrModule, FlowModule, FlowArgs, FlowOpts) ->
    StartFun = fun (EnrichedFlowOpts) ->
        supervisor:start_child(?REF(NodeName, FlowMgrModule, FlowModule), [FlowArgs, EnrichedFlowOpts])
    end,
    axb_flow:start_sup(StartFun, FlowOpts).


%%
%%  Start flow, and wait for its response synchronously.
%%
start_sync_flow(NodeName, FlowMgrModule, FlowModule, FlowArgs, FlowOpts) ->
    case start_flow(NodeName, FlowMgrModule, FlowModule, FlowArgs, FlowOpts) of
        {ok, FlowId} ->
            Timeout = proplists:get_value(timeout, FlowOpts, 5000),
            axb_flow:wait_response(FlowId, Timeout);
        {error, Reason} ->
            {error, Reason}
    end.



%%% ============================================================================
%%% Callbacks for supervisor.
%%% ============================================================================

%%
%%  Supervisor initialization.
%%
init({NodeName, FlowMgrModule, FlowDomain, FlowModule, Opts}) ->
    DefaultMFA = {axb_flow, start_link, [NodeName, FlowMgrModule, FlowDomain, FlowModule]},
    DefaultMods = [axb_flow, FlowModule],
    FlowMFA = proplists:get_value(mfa, Opts, DefaultMFA),
    FlowMods = proplists:get_value(modules, Opts, DefaultMods),
    DefaultSpec = {FlowModule, FlowMFA, transient, 1000, worker, FlowMods},
    ChildSpec = proplists:get_value(spec, Opts, DefaultSpec),
    lager:debug(
        "Starting flow supervisor for node=~p, flow_mgr=~p, flow=~p with child_spec=~p",
        [NodeName, FlowMgrModule, FlowModule, ChildSpec]
    ),
    ok = axb_flow_mgr:register_flow(NodeName, FlowMgrModule, FlowDomain, FlowModule, false),
    {ok, {{simple_one_for_one, 100, 1000}, [ChildSpec]}}.


