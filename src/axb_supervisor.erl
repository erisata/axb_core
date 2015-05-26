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
%%% A supervisor that handles starting and stopping child processes
%%% more conveniently. This supervisor should be useful for implementing
%%% adapters, when some processes should be started/stopped depending
%%% on the adapter's operation mode.
%%%
-module(axb_supervisor).
-behaviour(supervisor).
-compile([{parse_transform, lager_transform}]).
-export([start_link/3, start_child/1, stop_child/1]).
-export([init/1]).

%%% ============================================================================
%%% Callback definitions.
%%% ============================================================================

%%
%%  Corresponds to the `supervisor:init/1` callback.
%%
-callback init(
        Args :: term()
    ) ->
        {ok, SupSpec :: term()} |
        ignore.



%%% ============================================================================
%%% API functions.
%%% ============================================================================

%%
%%
%%
start_link(Name, Module, Args) ->
    supervisor:start_link(Name, Module, {Module, Args}).


%%
%%  Start or restart a child by given specification.
%%
start_child({ChildId, _StartFunc, _Restart, _Shutdown, _Type, _Modules} = StartSpec) ->
    case supervisor:start_child(?MODULE, StartSpec) of
        {ok, _Child} ->
            ok;
        {error, {already_started, _Child}} ->
            ok;
        {error, already_present} ->
            {ok, _Child} = supervisor:restart_child(?MODULE, ChildId),
            ok
    end.


%%
%%  Stop the given child, if exists.
%%
stop_child({ChildId, _StartFunc, _Restart, _Shutdown, _Type, _Modules}) ->
    case supervisor:terminate_child(?MODULE, ChildId) of
        ok ->
            ok;
        {error, not_found} ->
            ok
    end.



%%% ============================================================================
%%% Callbacks for `supervisor`.
%%% ============================================================================

%%
%%
%%
init({Module, Args}) ->
    Module:init(Args).


