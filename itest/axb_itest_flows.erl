%/--------------------------------------------------------------------
%| Copyright 2013-2015 Erisata, UAB (Ltd.)
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
%%% Flow supervisor example.
%%%
-module(axb_itest_flows).
-behaviour(axb_flow_pool).
-compile([{parse_transform, lager_transform}]).
-export([start_link/1]).
-export([init/1, code_change/2]).


%%% ============================================================================
%%% Public API.
%%% ============================================================================

%%
%%  Create this Flow Supervisor.
%%
start_link(Mode) ->
    axb_flow_pool:start_link(axb_itest_node:name(), ?MODULE, Mode, []).



%%% ============================================================================
%%% `axb_flow_pool` callbacks.
%%% ============================================================================

%%
%%  Initialize it.
%%
init(empty) ->
    {ok, []};

init(single) ->
    {ok, [
        {axb_itest_flow, {}}
    ]}.

%%
%%
%%
code_change(_OldVsn, _Extra) ->
    ok.


