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
%%% Supervisor maintaining all flow supervisors for the application.
%%%
-module(axb_flow_sup_pool).
-compile([{parse_transform, lager_transform}]).
% -behaviour(axb_flow_sup).
% -behaviour(supervisor).
% -export([start_spec/2, start_link/1]).
% -export([start_flow/4, register_flow/2, unregister_flow/2]).
% -export([init/1]).
%
% -define(REF(NodeName), {via, gproc, {n, l, {?MODULE, NodeName}}}).
%
%
% %% =============================================================================
% %%  Callback definitions.
% %% =============================================================================
%
% -callback supervisor_start_spec(NodeName) ->
%     ok.
%
%
%
% %% =============================================================================
% %%  Public API.
% %% =============================================================================
%
% %%
% %%
% %%
% start_spec(SpecId, {Module, Function, Args}) ->
%     {SpecId,
%         {Module, Function, Args},
%         permanent, brutal_kill, supervisor,
%         [Module, ?MODULE]
%     };
%
% start_spec(SpecId, NodeName) ->
%     {SpecId,
%         {?MODULE, start_link, [NodeName]},
%         permanent, brutal_kill, supervisor,
%         [?MODULE]
%     }.
%
%
% %%
% %%
% %%
% start_link(NodeName) ->
%     supervisor:start_link(?REF(NodeName), ?MODULE, {}).
%
%
% %%
% %%  Implements `axb_flow_sup` behaviour.
% %%
% start_flow(NodeName, FlowModule, Args, Opts) ->
%     axb_flow_sup_sofo:start_flow(NodeName, FlowModule, Args, Opts).
%
%
% %%
% %%
% %%
% register_flow(NodeName, FlowModule) ->
%     case axb_flow:describe(NodeName, FlowModule, sup_spec) of
%         undefined ->
%             ok;
%         {ok, ChildSpec} ->
%             {ok, _ChildPid} = supervisor:start_child(?REF(NodeName), ChildSpec),
%             ok
%     end.
%
%
% %%
% %%
% %%
% unregister_flow(NodeName, FlowModule) ->
%     case supervisor:terminate_child(?REF(NodeName), FlowModule) of
%         ok ->
%             ok = supervisor:delete_child(?REF(NodeName), FlowModule),
%             ok;
%         {error, not_found} ->
%             {error, not_found}
%     end.
%
%
%
% %% =============================================================================
% %%  `supervisor` callbacks
% %% =============================================================================
%
% %%
% %%
% %%
% init({}) ->
%     {ok, {{one_for_one, 100, 1000}, []}}.
%
%
