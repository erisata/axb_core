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
%%% Behaviour for flows, that have its own supervisor.
%%% Used by the `axb_flow_pool`.
%%%
-module(axb_flow_supervised).
-compile([{parse_transform, lager_transform}]).
-export([sup_start_spec/2]).


%%% ============================================================================
%%% Callback definitions.
%%% ============================================================================

%%
%%  This callback should return a supervisor's child spec for the flow supervisor.
%%
-callback sup_start_spec(
        Args :: term()
    ) ->
        {ok, supervisor:child_spec()} |
        {error, Reason :: term()}.



%%% ============================================================================
%%% API functions.
%%% ============================================================================

%%
%%  Invokes `sup_start_spec/1` callback.
%%
sup_start_spec(Module, Args) ->
    Module:sup_start_spec(Args).


