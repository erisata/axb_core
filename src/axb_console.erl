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
%%% AxB Console implementation.
%%% Functions in this module are invoked from the shell script.
%%%
-module(axb_console).
-compile([{parse_transform, lager_transform}]).
-export([status/1, stats/1, completion/1, set_online/1]).

%%% ============================================================================
%%% Public API.
%%% ============================================================================

%%
%%  Print main components and their statuses.
%%
status([]) ->
    ok = axb:i(main).


%%
%%  Print current statistics.
%%
stats([]) ->
    ok = axb:i(stats).


%%
%%  List AxB elements. This is used for bash completion.
%%
%%  TODO: Fix it.
%%
completion([]) ->
    {ok, Nodes} = axb:info(nodes),
    ok = print_list([ N || {N, _S} <- Nodes]),
    ok;

completion([NodeNameStr]) ->
    NodeName = erlang:list_to_existing_atom(NodeNameStr),
    {ok, Adapters} = axb_node:info(NodeName, adapters),
    {ok, FlowMgrs} = axb_node:info(NodeName, flow_mgrs),
    ok = print_list([ N || {N, _S} <- Adapters ++ FlowMgrs]),
    ok;

completion([NodeNameStr, NodeElemStr | OtherArgs]) ->
    NodeName = erlang:list_to_existing_atom(NodeNameStr),
    case node_elem(NodeName, NodeElemStr) of
        {adapter, AdapterModule} ->
            case OtherArgs of
                [] ->
                    {ok, Domains} = axb_adapter:info(NodeName, AdapterModule, domains),
                    ok = print_list([all, internal, external | [ D || {D, _I, _E} <- Domains]]);
                ["internal"] ->
                    ok = print_list([]);
                ["external"] ->
                    ok = print_list([]);
                [_DomainStr] ->
                    ok = print_list([internal, external, both, all]);
                [_DomainStr, _DirectionStr | _] ->
                    ok = print_list([])
            end;
        {flow_mgr, FlowMgrModule} ->
            case OtherArgs of
                [] ->
                    {ok, Domains} = axb_flow_mgr:info(NodeName, FlowMgrModule, domains),
                    {ok, Flows}   = axb_flow_mgr:info(NodeName, FlowMgrModule, flows),
                    ok = print_list([all | [ D || {D, _S} <- Domains ] ++ [ F || {F, _S} <- Flows ]]);
                [_ | _] ->
                    ok = print_list([])
            end
    end,
    ok.


%%
%%  Change the online-status for a flow manager or an adapter.
%%  See `priv/axb` for command line arguments.
%%
set_online([OnlineStr, NodeNameStr, NodeElemStr | What]) ->
    Online = erlang:list_to_existing_atom(OnlineStr),
    NodeName = erlang:list_to_existing_atom(NodeNameStr),
    case node_elem(NodeName, NodeElemStr) of
        {adapter, AdapterModule} ->
            {Domain, Direction} = case What of
                []           -> {all, both};
                ["all"]      -> {all, both};
                ["internal"] -> {all, internal};
                ["external"] -> {all, external};
                [DomainStr | Other] ->
                    Dom = erlang:list_to_existing_atom(DomainStr),
                    case Other of
                        []           -> {Dom, both};
                        ["internal"] -> {Dom, internal};
                        ["external"] -> {Dom, external}
                    end
            end,
            ok = axb_adapter:domain_online(NodeName, AdapterModule, Domain, Direction, Online),
            io:format(
                "OK, ~p node adapter ~p domains ~p made online=~p in ~p directions.~n",
                [NodeName, AdapterModule, Domain, Online, Direction]
            ),
            ok;
        {flow_mgr, FlowMgrModule} ->
            FlowNames = case What of
                []                -> all;
                ["all"]           -> all;
                [DomainOrFlowStr] -> erlang:list_to_existing_atom(DomainOrFlowStr)
            end,
            ok = axb_flow_mgr:flow_online(NodeName, FlowMgrModule, FlowNames, Online),
            io:format(
                "OK, ~p node flow manager ~p flows ~p made online=~p.~n",
                [NodeName, FlowMgrModule, FlowNames, Online]
            ),
            ok;
        undefined ->
            io:format("ERROR: Node ~p has no adapter or flow manager named ~p.~n", [NodeName, NodeElemStr])
    end,
    ok.



%%
%%  Helper function.
%%
print_list(AtomList) ->
    StrList = lists:map(fun erlang:atom_to_list/1, lists:sort(AtomList)),
    io:format("~s~n", [string:join(StrList, " ")]),
    ok.


%%
%%  Determines node element type.
%%
node_elem(NodeName, NodeElemStr) ->
    NodeElem = erlang:list_to_existing_atom(NodeElemStr),
    {ok, Adapters} = axb_node:info(NodeName, adapters),
    {ok, FlowMgrs} = axb_node:info(NodeName, flow_mgrs),
    case {lists:keymember(NodeElem, 1, Adapters), lists:keymember(NodeElem, 1, FlowMgrs)} of
        {true,  false} -> {adapter, NodeElem};
        {false, true } -> {flow_mgr, NodeElem};
        {false, false} -> undefined
    end.


