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

%%
%%  Testcases for `axb_core`.
%%
-module(axb_core_SUITE).
-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([
    test_node_registration/1
]).
-include_lib("common_test/include/ct.hrl").
-include_lib("axb_core/include/axb.hrl").

%%
%%  CT API.
%%
all() ->
    [
        test_node_registration
    ].


%%
%%  CT API, initialization.
%%
init_per_suite(Config) ->
    application:load(lager),
    application:set_env(lager, handlers, [{lager_console_backend, debug}]),
    {ok, Apps} = application:ensure_all_started(axb_core),
    [{axb_apps, Apps} | Config].


%%
%%  CT API, cleanup.
%%
end_per_suite(Config) ->
    ok = lists:foreach(
        fun (A) -> application:stop(A) end,
        proplists:get_value(axb_apps, Config)
    ),
    ok.


have_node(Name) ->
    {ok, Nodes} = axb:info(nodes),
    lists:member(Name, Nodes).


unlink_kill(Pid) ->
    erlang:unlink(Pid),
    erlang:exit(Pid, kill),
    ok.


%% =============================================================================
%%  Testcases.
%% =============================================================================

%%
%%  Check is node registration / unregistration works.
%%
test_node_registration(_Config) ->
    false = have_node(axb_itest_node:name()),
    {ok, Pid} = axb_itest_node:start_link(),
    timer:sleep(50),
    true = have_node(axb_itest_node:name()),
    ok = unlink_kill(Pid),
    timer:sleep(50),
    false = have_node(axb_itest_node:name()),
    ok.


