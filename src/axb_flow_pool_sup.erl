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
%%% Supervisor for all flow supervisors in the `axb_flow_pool`.
%%%
-module(axb_flow_pool_sup).
-compile([{parse_transform, lager_transform}]).
-behaviour(supervisor).
-export([start_link/2]).
-export([add_flow_sup/4, remove_flow_sup/3]).
-export([init/1]).

-define(REF(NodeName, FlowMgrModule), {via, gproc, {n, l, {?MODULE, NodeName, FlowMgrModule}}}).


%%% ============================================================================
%%% API functions.
%%% ============================================================================

%%
%%  Start this supervisor.
%%
start_link(NodeName, FlowMgrModule) ->
    supervisor:start_link(?REF(NodeName, FlowMgrModule), ?MODULE, {}).


%%
%%  Add a supervisor for the specific flow.
%%
add_flow_sup(NodeName, FlowMgrModule, _FlowModule, SupStartSpec) ->
    case supervisor:start_child(?REF(NodeName, FlowMgrModule), SupStartSpec) of
        {ok, SupPid} ->
            {ok, SupPid};
        {error, Reason} ->
            {error, Reason}
    end.


%%
%%  Remove a supervisor for the specific flow.
%%
remove_flow_sup(NodeName, FlowMgrModule, FlowModule) ->
    case supervisor:terminate_child(?REF(NodeName, FlowMgrModule), FlowModule) of
        ok ->
            ok = supervisor:delete_child(?REF(NodeName, FlowMgrModule), FlowModule),
            ok;
        {error, not_found} ->
            {error, not_found}
    end.



%%% ============================================================================
%%% Callbacks for supervisor.
%%% ============================================================================

%%
%%  Supervisor initialization.
%%
init({}) ->
    {ok, {{one_for_one, 100, 1000}, []}}.


