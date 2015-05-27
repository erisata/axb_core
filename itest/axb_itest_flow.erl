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
%%% Flow implementation for tests.
%%%
-module(axb_itest_flow).
-behaviour(axb_flow).
-behaviour(axb_flow_supervised).
-compile([{parse_transform, lager_transform}]).
-export([perform/1]).
-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3, terminate/3, code_change/4]).
-export([transforming/2, saving/2, responding/2]).
-export([sup_start_spec/1]).


% TODO: Domains.


%%% ============================================================================
%%% Public API.
%%% ============================================================================

%%
%%  Start this flow under the flow supervisor.
%%  This is an alternative for the `start_link/1` function.
%%
perform(Message) ->
    {ok, FlowId} = axb_flow_sup_sofo:start_flow(axb_itest_node:name(), axb_itest_flows, ?MODULE, {Message}, []),
    lager:debug("Flow ~p started, flowId=~p", [?MODULE, FlowId]),
    axb_flow:wait_response(FlowId, 1000).


%%% ============================================================================
%%% `axb_flow_supervised` callbacks.
%%% ============================================================================

%%
%%  Return start specification for the corresponding flow supervisor.
%%
sup_start_spec(_Args) ->
    axb_flow_sup_sofo:sup_start_spec(axb_itest_node:name(), axb_itest_flows, ?MODULE, []).



%%% ============================================================================
%%% Internal state.
%%% ============================================================================

-record(state, {
    message
}).


%%% ============================================================================
%%% `axb_flow` callbacks.
%%% ============================================================================

%%
%%
%%
init({Message}) ->
    lager:debug("Initialized, param=~p", [Message]),
    {ok, transforming, #state{message = Message}, 0}.



%%
%%
%%
transforming(timeout, StateData) ->
    lager:debug("Transforming"),
    {next_state, saving, StateData, 0}.


%%
%%
%%
saving(timeout, StateData) ->
    lager:debug("Saving"),
    {next_state, responding, StateData, 0}.


%%
%%
%%
responding(timeout, StateData) ->
    lager:debug("Responding"),
    axb_flow:respond({ok, saved}),
    {stop, normal, StateData}.


handle_event(_Event, StateName, StateData) ->
    {next_state, StateName, StateData}.


handle_sync_event(_Event, _From, StateName, StateData) ->
    {reply, undefined, StateName, StateData}.


handle_info(_Info, StateName, StateData) ->
    {next_state, StateName, StateData}.


terminate(_Reason, _StateName, _StateData) ->
    ok.

code_change(_OldVsn, StateName, StateData, _Extra) ->
    {ok, StateName, StateData}.




