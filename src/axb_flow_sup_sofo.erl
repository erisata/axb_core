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
% -behaviour(axb_flow_sup).
% -behaviour(supervisor).
% -export([start_spec/2, start_link/2]).
% -export([start_flow/4, register_flow/2, unregister_flow/2]).
% -export([init/1]).
%
% -define(REF(NodeName, FlowModule), {via, gproc, {n, l, {?MODULE, NodeName, FlowModule}}}).
%
%
% %% =============================================================================
% %% API functions.
% %% =============================================================================
%
% %%
% %%
% %%
% start_spec(SpecId, FlowModule, FlowArgs) ->
%     {SpecId,
%         {?MODULE, start_link, [NodeName, FlowModule]},
%         permanent, brutal_kill, supervisor,
%         [Module, ?MODULE]
%     }.
%
%
% %%
% %%  Start this supervisor.
% %%
% start_link(NodeName, FlowModule) ->
%     supervisor:start_link(?REF(NodeName, FlowModule), ?MODULE, {NodeName, FlowModule}).
%
%
% %%
% %%  Start new flow under this supervisor.
% %%
% start_flow(NodeName, FlowModule, Args, Opts) ->
%     supervisor:start_child(?REF(NodeName, FlowModule), [Args, Opts]).
%
%
% %%
% %%
% %%
% register_flow(_NodeName, _FlowModule) ->
%     ok.
%
%
% %%
% %%
% %%
% unregister_flow(_NodeName, _FlowModule) ->
%     ok.
%
%
%
% %% =============================================================================
% %% Callbacks for supervisor.
% %% =============================================================================
%
% %%
% %%  Supervisor initialization.
% %%
% init({NodeName, FlowModule}) ->
%     {ok, ChildSpec} = axb_flow:describe(NodeName, FlowModule, start_spec),
%     {ok, {{simple_one_for_one, 100, 1000}, [ChildSpec]}}.
%
%
