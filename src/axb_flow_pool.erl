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
%%% Implementation of the flow manager (`flow_mgr`), that maintains
%%% a list of supervisors, one for each flow type.
%%%
-module(axb_flow_pool).
-compile([{parse_transform, lager_transform}]).
-behaviour(supervisor).
-export([start_link/4]).
-export([init/1]).

-define(REF(NodeName, Module), {via, gproc, {n, l, {?MODULE, NodeName, Module}}}).


%%% ============================================================================
%%% Callback definitions.
%%% ============================================================================

%%
%%  Should return the initial configuration for the flow supervisor.
%%
-callback init(
        Args    :: term()
    ) ->
        {ok, [Domain], [FlowSupSpec]}
    when
        FlowSupSpec :: {FlowModule, FlowArgs} | FlowModule,
        FlowModule  :: module(),
        FlowArgs    :: term(),
        Domain      :: atom().


%%
%%  This callback is invoked on code upgrades.
%%
-callback code_change(
        OldVsn :: term(),
        Extra :: term()
    ) ->
        ok.


%%% ============================================================================
%%% Public API.
%%% ============================================================================

%%
%%  Start this flow supervisor (its root supervisor).
%%
start_link(NodeName, Module, Args, Opts) ->
    supervisor:start_link(?REF(NodeName, Module), ?MODULE, {NodeName, Module, Args, Opts}).



%%% ============================================================================
%%% `supervisor` callbacks
%%% ============================================================================

%%
%%  Creates supervisor configuration.
%%
init({NodeName, Module, Args, Opts}) ->
    MgrSpec = {mgr,
        {axb_flow_pool_mgr, start_link, [NodeName, Module, Args, Opts]},
        permanent, 1000, worker, [axb_flow_pool_mgr, ?MODULE]
    },
    SupSpec = {sup,
        {axb_flow_pool_sup, start_link, [NodeName, Module]},
        permanent, 1000, supervisor, [axb_flow_pool_sup]
    },
    {ok, {{one_for_all, 100, 1000}, [SupSpec, MgrSpec]}}.


