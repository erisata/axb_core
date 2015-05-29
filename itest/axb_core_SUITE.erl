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
-compile([{parse_transform, lager_transform}]).
-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([
    test_node_registration/1,
    test_adapter_registration/1,
    test_adapter_domains/1,
    test_flow_mgr_registration/1,
    test_flow_pool/1,
    test_info/1,
    test_stats/1
]).
-include_lib("common_test/include/ct.hrl").
-include_lib("axb_core/include/axb.hrl").

%%
%%  CT API.
%%
all() ->
    [
        test_node_registration,
        test_adapter_registration,
        test_adapter_domains,
        test_flow_mgr_registration,
        test_flow_pool,
        test_info,
        test_stats
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
    lists:member({Name, running}, Nodes).


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
    lager:debug("Testcase test_node_registration - start"),
    Node = axb_itest_node:name(),
    false = have_node(Node),
    % Start the node.
    {ok, NodePid} = axb_itest_node:start_link(empty),
    timer:sleep(50),
    true = have_node(Node),
    {ok, []} = axb_node:info(Node, adapters),
    ok = unlink_kill(NodePid),
    % Terminate the node, it should be unregistered.
    timer:sleep(50),
    false = have_node(Node),
    ok.


%%
%%  Check if adapter can be registered to the node, and
%%  if the node waits for adapters.
%%
test_adapter_registration(_Config) ->
    lager:debug("Testcase test_adapter_registration - start"),
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
    timer:sleep(50),
    ok.


%%
%%  Test adapter domains.
%%
test_adapter_domains(_Config) ->
    lager:debug("Testcase test_adapter_domains - start"),
    Node = axb_itest_node:name(),
    %
    % Start the node, it should wait for the adapter.
    {ok, NodePid} = axb_itest_node:start_link(adapter),
    {ok, AdapterPid} = axb_itest_adapter:start_link(single),
    timer:sleep(50),
    true = have_node(Node),
    true = erlang:is_process_alive(NodePid),
    {ok, [{axb_itest_adapter, running}]} = axb_node:info(Node, adapters),
    {ok, [{main, true, true}]} = axb_adapter:info(Node, axb_itest_adapter, domains),
    {ok, a1} = axb_itest_adapter:send_message(a1),
    {ok, a2} = axb_itest_adapter:message_received(a2),
    %
    % Disable domains.
    ok = axb_adapter:domain_online(Node, axb_itest_adapter, main, all, false),
    {ok, [{main, false, false}]} = axb_adapter:info(Node, axb_itest_adapter, domains),
    {error, domain_offline} = axb_itest_adapter:send_message(a1),
    {error, domain_offline} = axb_itest_adapter:message_received(a2),
    %
    % Enable internal domain.
    ok = axb_adapter:domain_online(Node, axb_itest_adapter, main, internal, true),
    {ok, [{main, true, false}]} = axb_adapter:info(Node, axb_itest_adapter, domains),
    {ok, a3}                 = axb_itest_adapter:send_message(a3),
    {error, domain_offline} = axb_itest_adapter:message_received(a4),
    %
    % External domain online also.
    ok = axb_adapter:domain_online(Node, axb_itest_adapter, main, external, true),
    {ok, [{main, true, true}]} = axb_adapter:info(Node, axb_itest_adapter, domains),
    {ok, a5} = axb_itest_adapter:send_message(a5),
    {ok, a6} = axb_itest_adapter:message_received(a6),
    %
    % Cleanup.
    ok = unlink_kill(NodePid),
    ok = unlink_kill(AdapterPid),
    timer:sleep(50),
    ok.


%%
%%  Check if flow manager (flow pool, in this case) can be registered
%%  to the node, and if the node waits for it.
%%
test_flow_mgr_registration(_Config) ->
    lager:debug("Testcase test_flow_mgr_registration - start"),
    Node = axb_itest_node:name(),
    %
    % Start the node, it should wait for the flow manager.
    {ok, NodePid} = axb_itest_node:start_link(flow_mgr),
    timer:sleep(50),
    false = have_node(Node),
    {ok, [{axb_itest_flows, down}]} = axb_node:info(Node, flow_mgrs),
    %
    % Start the flow manager, the node should be ready now.
    {ok, FlowMgrPid} = axb_itest_flows:start_link(empty),
    timer:sleep(50),
    true = have_node(Node),
    true = erlang:is_process_alive(NodePid),
    {ok, [{axb_itest_flows, running}]} = axb_node:info(Node, flow_mgrs),
    %
    % Kill the flow manager, it should left registered.
    ok = unlink_kill(FlowMgrPid),
    timer:sleep(50),
    true = have_node(Node),
    true = erlang:is_process_alive(NodePid),
    {ok, [{axb_itest_flows, down}]} = axb_node:info(Node, flow_mgrs),
    %
    % Restart the flow manager, it should reregister itself.
    {ok, FlowMgrPid2} = axb_itest_flows:start_link(empty),
    timer:sleep(50),
    true = have_node(Node),
    true = erlang:is_process_alive(NodePid),
    {ok, [{axb_itest_flows, running}]} = axb_node:info(Node, flow_mgrs),
    %
    % Unregister the flow manager explicitly, node should be running as the flow manager unregistered.
    ok = axb_node:unregister_flow_mgr(Node, axb_itest_flows),
    timer:sleep(50),
    true = have_node(Node),
    true = erlang:is_process_alive(NodePid),
    {ok, []} = axb_node:info(Node, flow_mgrs),
    %
    % Check if killing of the unregistered flow manager does not affect the node.
    ok = unlink_kill(FlowMgrPid2),
    timer:sleep(50),
    true = have_node(Node),
    true = erlang:is_process_alive(NodePid),
    {ok, []} = axb_node:info(Node, flow_mgrs),
    %
    % Cleanup.
    ok = unlink_kill(NodePid),
    timer:sleep(50),
    ok.


%%
%%  Check, if flow pool (implementation of the axb_flow_mgr) maintains flows properly.
%%
test_flow_pool(_Config) ->
    lager:debug("Testcase test_flow_pool - start"),
    Node = axb_itest_node:name(),
    %
    % Start the node and the manager, it should wait for the flow manager.
    {ok, NodePid} = axb_itest_node:start_link(flow_mgr),
    {ok, FlowMgrPid} = axb_itest_flows:start_link(single),
    timer:sleep(50),
    true = have_node(Node),
    true = erlang:is_process_alive(NodePid),
    {ok, [{axb_itest_flows, running}]} = axb_node:info(Node, flow_mgrs),
    {ok, [{axb_itest_flow, online}]} = axb_flow_mgr:info(Node, axb_itest_flows, flows),
    %
    % Start some supervised flows.
    {ok, saved} = axb_itest_flow:perform(msg),
    %
    % Make flow offline by domain.
    ok = axb_flow_mgr:flow_online(Node, axb_itest_flows, d1, false),
    {ok, [{axb_itest_flow, offline}]} = axb_flow_mgr:info(Node, axb_itest_flows, flows),
    {error, flow_offline} = axb_itest_flow:perform(msg),
    %
    % Make flow online by its name.
    ok = axb_flow_mgr:flow_online(Node, axb_itest_flows, axb_itest_flow, true),
    {ok, [{axb_itest_flow, online}]} = axb_flow_mgr:info(Node, axb_itest_flows, flows),
    {ok, saved} = axb_itest_flow:perform(msg),
    ok = unlink_kill(FlowMgrPid),
    ok = unlink_kill(NodePid),
    timer:sleep(50),
    ok.

%%
%%  Test, if axb info is returned correctly.
%%
test_info(_Config) ->
    lager:debug("Testcase test_info - start"),
    {ok, NodePid} = axb_itest_node:start_link(both),
    {ok, FlowMgrPid} = axb_itest_flows:start_link(single),
    {ok, AdapterPid} = axb_itest_adapter:start_link(single),
    timer:sleep(50),
    {ok, [
        {axb_itest, [
            {status, running},
            {adapters, [
                {axb_itest_adapter, [
                    {status, running},
                    {domains, [
                        {main, [
                            {internal, online},
                            {external, online}
                        ]}
                    ]}
                ]}
            ]},
            {flow_mgrs, [
                {axb_itest_flows, [
                    {status, running},
                    {flows, [
                        {axb_itest_flow, [
                            {status, online}
                        ]}
                    ]}
                ]}
            ]}
        ]}
    ]} = axb:info(details),
    {ok, [
        {axb_itest, running}
    ]} = axb:info(nodes),
    {ok, [
        {axb_itest, [
            {axb_itest_adapter, running}
        ]}
    ]} = axb:info(adapters),
    {ok, [
        {axb_itest, [
            {axb_itest_flows, running}
        ]}
    ]} = axb:info(flow_mgrs),
    {ok, [
        {axb_itest, [
            {axb_itest_flows, [
                {axb_itest_flow, online}
            ]}
        ]}
    ]} = axb:info(flows),
    ok = unlink_kill(AdapterPid),
    ok = unlink_kill(FlowMgrPid),
    ok = unlink_kill(NodePid),
    timer:sleep(50),
    ok.


%%
%%  Check, if statistics are collected.
%%
test_stats(_Config) ->
    lager:debug("Testcase test_stats - start"),
    {ok, NodePid} = axb_itest_node:start_link(both),
    {ok, FlowMgrPid} = axb_itest_flows:start_link(single),
    {ok, AdapterPid} = axb_itest_adapter:start_link(single),
    timer:sleep(50),
    {ok, msg1} = axb_itest_adapter:send_message(msg1),
    {ok, msg2} = axb_itest_adapter:message_received(msg2),
    %
    % Check if stats created.
    {ok, StatNames} = axb_stats:info(list),
    true = length(StatNames) > 0,
    true = lists:member([axb, axb_itest, ad], StatNames),
    true = lists:member([axb, axb_itest, ad, axb_itest_adapter], StatNames),
    true = lists:member([axb, axb_itest, ad, axb_itest_adapter, main], StatNames),
    true = lists:member([axb, axb_itest, ad, axb_itest_adapter, main, internal], StatNames),
    true = lists:member([axb, axb_itest, ad, axb_itest_adapter, main, internal, send_message, epm], StatNames),
    true = lists:member([axb, axb_itest, ad, axb_itest_adapter, main, internal, send_message, dur], StatNames),
    true = lists:member([axb, axb_itest, ad, axb_itest_adapter, main, external], StatNames),
    true = lists:member([axb, axb_itest, ad, axb_itest_adapter, main, external, message_received, epm], StatNames),
    true = lists:member([axb, axb_itest, ad, axb_itest_adapter, main, external, message_received, dur], StatNames),
    true = lists:member([axb, axb_itest, fm], StatNames),
    true = lists:member([axb, axb_itest, fm, axb_itest_flows], StatNames),
    true = lists:member([axb, axb_itest, fm, axb_itest_flows, d1], StatNames),
    true = lists:member([axb, axb_itest, fm, axb_itest_flows, d1, axb_itest_flow, epm], StatNames),
    true = lists:member([axb, axb_itest, fm, axb_itest_flows, d1, axb_itest_flow, dur], StatNames),
    %
    % Update some stats.
    {ok, [{count, C1}]} = exometer:get_value([axb, axb_itest, fm, axb_itest_flows, d1, axb_itest_flow, epm], count),
    {ok, saved} = axb_itest_flow:perform(msg),
    {ok, [{count, C2}]} = exometer:get_value([axb, axb_itest, fm, axb_itest_flows, d1, axb_itest_flow, epm], count),
    true = C2 > C1,
    %
    % Cleanup.
    ok = unlink_kill(AdapterPid),
    ok = unlink_kill(FlowMgrPid),
    ok = unlink_kill(NodePid),
    timer:sleep(50),
    ok.


