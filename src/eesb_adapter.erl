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
%%% TODO: ESB Adapter behaviour.
%%%
%%% Main functions of this behaviour are the following:
%%%
%%%   * Allow management of services, provided by the adapter (disable temporary, etc.);
%%%   * Collect metrics of the adapter operation;
%%%   * Define metada, describing the adapter.
%%%
%%% This behaviour is implemented not using a dedicated process,
%%% in order to avoid bootleneck when processing adapter commands.
%%%
-module(eesb_adapter).
-behaviour(gen_server).


%% =============================================================================
%%  Callback definitions.
%% =============================================================================

%%
%%
%%
-callback handle_describe(
        NodeName    :: term(),
        What        :: start_spec | sup_spec | meta
    ) ->
        {ok, Info :: term()}.


%%
%%
%%
-callback handle_mode_change(
        NodeName        :: atom(),
        AdapterModule   :: module(),
        Services        :: [Service :: atom()] | all,
        Mode            :: online | offline,
        Direction       :: internal | external | all
    ) ->
        ok.

%%
%%
%%
-spec set_mode(
        NodeName        :: atom(),
        AdapterModule   :: module(),
        Services        :: [Service :: atom()] | all,
        Mode            :: online | offline,
        Direction       :: internal | external | all
    ) ->
        ok.

set_mode(NodeName, AdapterModule, Services, Mode, Direction) ->
    ok.
