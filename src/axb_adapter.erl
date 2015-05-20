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
%%%   * Define metadata, describing the adapter.
%%%
%%% This behaviour is implemented not using a dedicated process,
%%% in order to avoid bootleneck when processing adapter commands.
%%% This also allows to have any structure for the particular adapter,
%%% in terms of processes and supervision tree.
%%%
-module(axb_adapter).
-export([register/3, set_mode/5]).


%%% =============================================================================
%%% Callback definitions.
%%% =============================================================================

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

%%% =============================================================================
%%% Public API.
%%% =============================================================================

%%
%%  Register an adapter to the specific node.
%%  The calling process will be linked with the node
%%  and will represent the adapter (termination will
%%  cause unregistering of the adapter).
%%
%%  No options are currently supported.
%%
-spec register(
        NodeName        :: atom(),
        AdapterModule   :: module(),
        Opts            :: list()
    ) ->
        ok |
        {error, Reason :: term()}.

register(NodeName, AdapterModule, Opts) ->
    axb_node:register_adapter(NodeName, AdapterModule, Opts).


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


