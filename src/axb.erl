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
-module(axb).
-compile([{parse_transform, lager_transform}]).
-export([start/0, info/0, info/1, i/0, i/1, make_id/0]).


%%% =============================================================================
%%% Public API.
%%% =============================================================================

%%
%% Start the application.
%%
start() ->
    application:ensure_all_started(axb_core).


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
%%  Prints AxB information.
%%
i() ->
    i(main).

i(main) ->
    PrintAdapterDomain = fun ({Domain, DomainProps}) ->
        Internal = proplists:get_value(internal, DomainProps),
        External = proplists:get_value(external, DomainProps),
        case {Internal, External} of
            {online,  online } -> io:format(" ~p[online]", [Domain]);
            {online,  offline} -> io:format(" ~p[internal-only]", [Domain]);
            {offline, online } -> io:format(" ~p[external-only]", [Domain]);
            {offline, offline} -> io:format(" ~p[offline]", [Domain])
        end
    end,
    PrintAdapter = fun ({AdapterModule, AdapterProps}) ->
        io:format("    ~p - ~p,", [AdapterModule, proplists:get_value(status, AdapterProps)]),
        ok = lists:foreach(PrintAdapterDomain, proplists:get_value(domains, AdapterProps)),
        io:format("~n")
    end,
    PrintFlow = fun ({FlowModule, FlowProps}) ->
        Status = proplists:get_value(status, FlowProps),
        Domain = proplists:get_value(domain, FlowProps),
        io:format("      ~p - running, ~p[~p]~n", [FlowModule, Domain, Status])
    end,
    PrintFlowMgr = fun ({FlowMgrModule, FlowMgrProps}) ->
        io:format("    ~p - ~p~n", [FlowMgrModule, proplists:get_value(status, FlowMgrProps)]),
        ok = lists:foreach(PrintFlow, proplists:get_value(flows, FlowMgrProps))
    end,
    PrintNode = fun ({NodeName, NodeProps}) ->
        io:format("  ~p - ~p~n", [NodeName, proplists:get_value(status, NodeProps)]),
        ok = lists:foreach(PrintFlowMgr, proplists:get_value(flow_mgrs, NodeProps)),
        ok = lists:foreach(PrintAdapter, proplists:get_value(adapters, NodeProps)),
        io:format("~n")
    end,
    case info(details) of
        {ok, []} ->
            io:format("  No AxB nodes registered.~n");
        {ok, Nodes} ->
            ok = lists:foreach(PrintNode, Nodes)
    end,
    ok;

i(stats) ->
    {ok, Stats} = axb_stats:info(main),
    PrintStatSepFun = fun () ->
        io:format("+-~-15c-+-~-15c-+-~-15c-+-~-64c-~n", [$-, $-, $-, $-])
    end,
    PrintStatHdrFun = fun () ->
        io:format("| ~-15s | ~-15s | ~-15s | ~s~n", ["Ops/min", "Err/min", "Time mean [ms]", "What"])
    end,
    PrintStatLineFun = fun ({Name, Epm, _Eph, _Epd, _Epl, Err, _Erh, _Erd, _Erl, Dur}) ->
        io:format("| ~15B | ~15B | ~15.3f | ~w~n", [Epm, Err, Dur / 1000, Name])
    end,
    PrintStatSepFun(),
    PrintStatHdrFun(),
    PrintStatSepFun(),
    ok = lists:foreach(PrintStatLineFun, Stats),
    PrintStatSepFun(),
    ok.


%%
%%  Create new unique ID.
%%
make_id() ->
    IdTerm = {erlang:node(), erlang:monotonic_time(), erlang:unique_integer([monotonic])},
    SHA = crypto:hash(sha, erlang:term_to_binary(IdTerm)),
    iolist_to_binary([io_lib:format("~2.16.0B", [X]) || X <- binary_to_list(SHA)]).


