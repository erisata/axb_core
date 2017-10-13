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
%%% Pipeline EIP implementation for tests.
%%%
-module(axb_itest_eip_pipeline).
-behaviour(axb_eip_pipeline).
-behaviour(axb_flow_supervised).
-compile([{parse_transform, lager_transform}]).
-export([test_cast/1, test_call/1]).
-export([init/1, handle_step/2]).
-export([sup_start_spec/1]).


%%% ============================================================================
%%% Public API.
%%% ============================================================================

%%
%%  Test asynchronous pipeline.
%%
test_cast(Input) ->
    case axb_flow_sup_sofo:start_flow(axb_itest_node:name(), axb_itest_flows, ?MODULE, Input, []) of
        {ok, FlowId} ->
            lager:debug("Flow ~p:test_context_adapter/0 started, flowId=~p", [?MODULE, FlowId]),
            axb_eip_pipeline:wait_response(FlowId, 1000);
        {error, Reason} ->
            {error, Reason}
    end.

%%
%%  Test synchronous pipeline.
%%
test_call(Input) ->
    axb_flow_sup_sofo:start_sync_flow(axb_itest_node:name(), axb_itest_flows, ?MODULE, Input, []).



%%% ============================================================================
%%% `axb_flow_supervised` callbacks.
%%% ============================================================================

%%
%%  Return start specification for the corresponding flow supervisor.
%%
sup_start_spec({Domain}) ->
    Node = axb_itest_node:name(),
    axb_flow_sup_sofo:sup_start_spec(Node, axb_itest_flows, Domain, ?MODULE, [
        {mfa, {axb_eip_pipeline, start_link, [Node, axb_itest_flows, Domain, ?MODULE]}},
        {modules, [axb_flow, axb_eip_pipeline, ?MODULE]}
    ]).



%%% ============================================================================
%%% `axb_eip_pipeline` callbacks.
%%% ============================================================================

%%
%%  Initialize.
%%
init(Input) ->
    {ok, [read, transform, save], Input}.

%%
%%  Handle all steps.
%%
handle_step(read, Input) ->
    lager:debug("Performing read, input=~p", [Input]),
    Output = {read, Input},
    {ok, Output};

handle_step(transform, Input) ->
    lager:debug("Performing transform, input=~p", [Input]),
    Output = {transform, Input},
    {ok, Output};

handle_step(save, Input) ->
    lager:debug("Performing save, input=~p", [Input]),
    Output = {save, Input},
    {ok, Output}.


