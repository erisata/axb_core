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
%%% Adapter supervisor for tests.
%%%
-module(axb_itest_adapter_sup).
-behaviour(axb_supervisor).
-compile([{parse_transform, lager_transform}]).
-export([start_link/1, start_listener/0, stop_listener/0]).
-export([init/1]).


%%% =============================================================================
%%% API functions.
%%% =============================================================================

%%
%%  Start this supervisor.
%%
start_link(Mode) ->
    axb_supervisor:start_link({local, ?MODULE}, ?MODULE, Mode).


%%
%%  Start business specific process.
%%
start_listener() ->
    axb_supervisor:start_child(?MODULE, child_spec(listener)).


%%
%%  Start business specific process.
%%
stop_listener() ->
    axb_supervisor:stop_child(?MODULE, child_spec(listener)).



%%% =============================================================================
%%% Callbacks for `supervisor`.
%%% =============================================================================

%%
%%
%%
init(Mode) ->
    {ok, {{one_for_all, 100, 10}, [
        child_spec({adapter, Mode})
    ]}}.



%%% =============================================================================
%%% Internal functions.
%%% =============================================================================

%%
%%
%%
child_spec({adapter, Mode}) ->
    {axb_itest_adapter,
        {axb_itest_adapter, start_link, [Mode]},
        permanent, brutal_kill, worker,
        [axb_adapter, axb_itest_adapter]
    };

child_spec(listener) ->
    {axb_itest_adapter_listener,
        {axb_itest_adapter_listener, start_link, []},
        permanent, brutal_kill, worker,
        [axb_itest_adapter_listener]
    }.
