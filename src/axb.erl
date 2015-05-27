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
%%% AxB API.
%%%
%%% Mainly acts as a facade to other modules.
%%%
%%% TODO: Add riak support.
%%% TODO: Add singleton functionality.
%%%
-module(axb).
-compile([{parse_transform, lager_transform}]).
-export([info/0, info/1, status/0, status/1]).


%%% =============================================================================
%%% Public API.
%%% =============================================================================

%%
%%  Returns AxB state:
%%
%%    * Nodes
%%    * Node adapters, flow supervisors, flows types.
%%
info() ->
    info(details).

info(details) ->
    {ok, Nodes} = axb_node_mgr:info(details),
    InfoFun = fun ({NodeName, NodeProps}) ->
        AdapterInfoFun = fun ({AdapterModule, AdapterProps}) ->
            {ok, AdapterDetails} = axb_adapter:info(NodeName, AdapterModule, details),
            {AdapterModule, AdapterProps ++ AdapterDetails}
        end,
        FlowMgrInfoFun = fun ({FlowMgrModule, FlowMgrProps}) ->
            {ok, FlowMgrDetails} = axb_flow_mgr:info(NodeName, FlowMgrModule, details),
            {FlowMgrModule, FlowMgrProps ++ FlowMgrDetails}
        end,
        {ok, NodeDetails} = axb_node:info(NodeName, details),
        {adapters,  NodeAdapters} = lists:keyfind(adapters,  1, NodeDetails),
        {flow_mgrs, NodeFlowMgrs} = lists:keyfind(flow_mgrs, 1, NodeDetails),
        NewNodeAdapters = lists:map(AdapterInfoFun, NodeAdapters),
        NewNodeFlowMgrs = lists:map(FlowMgrInfoFun, NodeFlowMgrs),
        NodeDetailsWithAdapters = lists:keyreplace(adapters,  1, NodeDetails,             {adapters,  NewNodeAdapters}),
        NodeDetailsWithFlowMgrs = lists:keyreplace(flow_mgrs, 1, NodeDetailsWithAdapters, {flow_mgrs, NewNodeFlowMgrs}),
        {NodeName, NodeProps ++ NodeDetailsWithFlowMgrs}
    end,
    {ok, lists:map(InfoFun, lists:sort(Nodes))};

info(nodes) ->
    axb_node_mgr:info(status);

info(adapters) ->
    {ok, NodeNames} = axb_node_mgr:info(list),
    InfoFun = fun (NodeName) ->
        {ok, Adapters} = axb_node:info(NodeName, adapters),
        {NodeName, lists:sort(Adapters)}
    end,
    {ok, lists:map(InfoFun, lists:sort(NodeNames))};

info(flow_mgrs) ->
    {ok, NodeNames} = axb_node_mgr:info(list),
    InfoFun = fun (NodeName) ->
        {ok, FlowMgrs} = axb_node:info(NodeName, flow_mgrs),
        {NodeName, lists:sort(FlowMgrs)}
    end,
    {ok, lists:map(InfoFun, lists:sort(NodeNames))};

info(flows) ->
    {ok, NodeNames} = axb_node_mgr:info(list),
    InfoFun = fun (NodeName) ->
        FlowInfoFun = fun ({FlowMgrModule, _FlowMgrStatus}) ->
            {ok, Flows} = axb_flow_mgr:info(NodeName, FlowMgrModule, flows),
            {FlowMgrModule, lists:sort(Flows)}
        end,
        {ok, FlowMgrs} = axb_node:info(NodeName, flow_mgrs),
        {NodeName, lists:map(FlowInfoFun, lists:sort(FlowMgrs))}
    end,
    {ok, lists:map(InfoFun, lists:sort(NodeNames))}.


%%
%%  Prints AxB state.
%%
status() ->
    status(all).

status(all) ->
    ok.


