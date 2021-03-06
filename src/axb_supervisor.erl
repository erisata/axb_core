%/--------------------------------------------------------------------
%| Copyright 2015-2017 Erisata, UAB (Ltd.)
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
-export([start_link/3, start_child/2, stop_child/2]).
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
    supervisor:start_link(Name, ?MODULE, {Module, Args}).


%%
%%  Start or restart a child by given specification.
%%
start_child(Name, {ChildId, _StartFunc, _Restart, _Shutdown, _Type, _Modules} = StartSpec) ->
    start_child(Name, ChildId, StartSpec);

start_child(Name, #{id := ChildId} = StartSpec) ->
    start_child(Name, ChildId, StartSpec).

start_child(Name, ChildId, StartSpec) ->
    case supervisor:start_child(Name, StartSpec) of
        {ok, _Child} ->
            ok;
        {error, {already_started, _Child}} ->
            ok;
        {error, already_present} ->
            {ok, _Child} = supervisor:restart_child(Name, ChildId),
            ok
    end.


%%
%%  Stop the given child, if exists.
%%
stop_child(Name, {ChildId, _StartFunc, _Restart, _Shutdown, _Type, _Modules}) ->
    stop_child(Name, {id, ChildId});

stop_child(Name, #{id := ChildId}) ->
    stop_child(Name, {id, ChildId});

stop_child(Name, {id, ChildId}) ->
    case supervisor:terminate_child(Name, ChildId) of
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


