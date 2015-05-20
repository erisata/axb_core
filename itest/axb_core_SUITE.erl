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
    test_node_registration/1,
    test_adapter_registration/1
]).
-include_lib("common_test/include/ct.hrl").
-include_lib("axb_core/include/axb.hrl").

%%
%%  CT API.
%%
all() ->
    [
        test_node_registration,
        test_adapter_registration
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
    Node = axb_itest_node:name(),
    false = have_node(Node),
    % Start the node.
    {ok, Pid} = axb_itest_node:start_link(empty),
    timer:sleep(50),
    true = have_node(Node),
    {ok, []} = axb_node:info(Node, adapters),
    ok = unlink_kill(Pid),
    % Terminate the node, it should be unregistered.
    timer:sleep(50),
    false = have_node(Node),
    ok.


%%
%%  Check if adapter can be registered to the node, and
%%  if the node waits for adapters.
%%
test_adapter_registration(_Config) ->
    Node = axb_itest_node:name(),
    %
    % Start the node, it should wait for the adapter.
    {ok, NodePid} = axb_itest_node:start_link(adapter),
    timer:sleep(50),
    false = have_node(Node),
    {ok, [{axb_itest_adapter, down}]} = axb_node:info(Node, adapters),
    %
    % Start the adapter, the node should be ready now.
    {ok, AdapterPid} = axb_itest_adapter:start_link(empty),
    timer:sleep(50),
    true = have_node(Node),
    true = erlang:is_process_alive(NodePid),
    {ok, [{axb_itest_adapter, running}]} = axb_node:info(Node, adapters),
    %
    % Kill the adapter, it should left registered.
    ok = unlink_kill(AdapterPid),
    timer:sleep(50),
    true = have_node(Node),
    true = erlang:is_process_alive(NodePid),
    {ok, [{axb_itest_adapter, down}]} = axb_node:info(Node, adapters),
    %
    % Restart adapter, it should reregister itself.
    {ok, AdapterPid2} = axb_itest_adapter:start_link(empty),
    timer:sleep(50),
    true = have_node(Node),
    true = erlang:is_process_alive(NodePid),
    {ok, [{axb_itest_adapter, running}]} = axb_node:info(Node, adapters),
    %
    % Unregister adapter explicitly, node should be running as the adapter unregistered.
    ok = axb_node:unregister_adapter(Node, axb_itest_adapter),
    timer:sleep(50),
    true = have_node(Node),
    true = erlang:is_process_alive(NodePid),
    {ok, []} = axb_node:info(Node, adapters),
    %
    % Check if killing of the unregistered adapter does not affect the node.
    ok = unlink_kill(AdapterPid2),
    timer:sleep(50),
    true = have_node(Node),
    true = erlang:is_process_alive(NodePid),
    {ok, []} = axb_node:info(Node, adapters),
    %
    % Cleanup.
    ok = unlink_kill(NodePid),
    ok.


%%
%%  TODO: Test adapter services.
%%


%%
%%  TODO: Check if flow supervisor can be registered to the node, and
%%  if the node waits for them.
%%


