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
%%% Behaviour for flow supervisor.
%%%
-module(eesb_flow_sup).
-export([start_flow/4, register_flow/2, unregister_flow/2]).


%% =============================================================================
%%  Callback definitions.
%% =============================================================================

%%
%%
%%
-callback start_flow(NodeName :: term(), FlowModule :: module(), Args :: term(), Opts :: list()) -> {ok, term()}.

%%
%%
%%
-callback register_flow(NodeName :: term(), FlowModule :: module()) -> ok.

%%
%%
%%
-callback unregister_flow(NodeName :: term(), FlowModule :: module()) -> ok.



%% =============================================================================
%%  API functions.
%% =============================================================================

%%
%%
%%
start_flow(NodeName, FlowModule, Args, Opts) ->
    {ok, SupModule} = eesb_node:flow_sup(NodeName),
    SupModule:start_flow(NodeName, FlowModule, Args, Opts).


%%
%%
%%
register_flow(NodeName, FlowModule) ->
    {ok, SupModule} = eesb_node:flow_sup(NodeName),
    SupModule:register_flow(NodeName, FlowModule).


%%
%%
%%
unregister_flow(NodeName, FlowModule) ->
    {ok, SupModule} = eesb_node:flow_sup(NodeName),
    SupModule:unregister_flow(NodeName, FlowModule).


