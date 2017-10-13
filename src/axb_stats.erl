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
%%% Collects and provides runtime statictics.
%%% Implemented using Exometer.
%%%
%%% Metric types are represented by name suffixes:
%%%
%%%   * epm -- executions / minute      (spiral).
%%%   * epd -- executions / day         (day_slots).
%%%   * err -- errors     / minute      (spiral).
%%%   * erd -- errors     / day         (day_slots).
%%%   * dur -- exec time in last min.   (spiral)???
%%%
-module(axb_stats).
-compile([{parse_transform, lager_transform}]).
-export([
    info/1,
    node_registered/1,
    adapter_registered/3,
    adapter_command_executed/6,
    flow_mgr_registered/3,
    flow_registered/4,
    flow_executed/5,
    get_flow_value/5,
    get_adapter_value/6
]).


%%% ============================================================================
%%% API functions.
%%% ============================================================================

%%
%%
%%
info(list) ->
    Entries = exometer:find_entries([axb]),
    {ok, [ Name || {Name, _Type, enabled} <- Entries ]};

info(main) ->
    AdapterInfoFun = fun ([axb, Node, ad, Ad, Dom, Dir, Cmd, epm]) ->
        Epm             = get_optional([axb, Node, ad, Ad, Dom, Dir, Cmd, epm], one),
        [Eph, Epd, Epl] = get_optional([axb, Node, ad, Ad, Dom, Dir, Cmd, epd], [h0, d0, last]),
        Err             = get_optional([axb, Node, ad, Ad, Dom, Dir, Cmd, err], one),
        [Erh, Erd, Erl] = get_optional([axb, Node, ad, Ad, Dom, Dir, Cmd, erd], [h0, d0, last]),
        Dur             = get_optional([axb, Node, ad, Ad, Dom, Dir, Cmd, dur], one), % TODO: Use mean or average instead of count.
        {[axb, Node, ad, Ad, Dom, Dir, Cmd], Epm, Eph, Epd, Epl, Err, Erh, Erd, Erl, Dur}
    end,
    FlowMgrInfoFun = fun ([axb, Node, fm, FM, Dom, Flow, epm]) ->
        Epm             = get_optional([axb, Node, fm, FM, Dom, Flow, epm], one),
        [Eph, Epd, Epl] = get_optional([axb, Node, fm, FM, Dom, Flow, epd], [h0, d0, last]),
        Err             = get_optional([axb, Node, fm, FM, Dom, Flow, err], one),
        [Erh, Erd, Erl] = get_optional([axb, Node, fm, FM, Dom, Flow, erd], [h0, d0, last]),
        Dur             = get_optional([axb, Node, fm, FM, Dom, Flow, dur], one),
        {[axb, Node, fm, FM, Dom, Flow], Epm, Eph, Epd, Epl, Err, Erh, Erd, Erl, Dur}
    end,
    AdapterEpmNames = [ N || {N, _T, _E} <- exometer:find_entries([axb, '_', ad, '_', '_', '_', '_', epm]) ],
    FlowMgrEpmNames = [ N || {N, _T, _E} <- exometer:find_entries([axb, '_', fm, '_', '_',      '_', epm]) ],
    {ok, lists:sort(
        lists:map(AdapterInfoFun, AdapterEpmNames) ++ lists:map(FlowMgrInfoFun, FlowMgrEpmNames)
    )}.


%%
%%  Creates aggregated metrics for the specified node.
%%
node_registered(NodeName) ->
    DataPoints = [count, one],
    MatchSpecAD = [{{[axb, NodeName, ad, '_', '_', '_', '_', epm], '_', '_'}, [], [true]}],
    MatchSpecFM = [{{[axb, NodeName, fm, '_', '_',      '_', epm], '_', '_'}, [], [true]}],
    ok = exometer:ensure(
        [axb, NodeName, ad],
        {function, exometer, aggregate, [MatchSpecAD, DataPoints], proplist, DataPoints},
        []
    ),
    ok = exometer:ensure(
        [axb, NodeName, fm],
        {function, exometer, aggregate, [MatchSpecFM, DataPoints], proplist, DataPoints},
        []
    ).


%%
%%  Creates aggregated metrics for the specified adapter.
%%
adapter_registered(NodeName, AdapterModule, Domains) ->
    DataPoints = [count, one],
    MatchSpecA = [{{[axb, NodeName, ad, AdapterModule, '_', '_', '_', epm], '_', '_'}, [], [true]}],
    ok = exometer:ensure(
        [axb, NodeName, ad, AdapterModule],
        {function, exometer, aggregate, [MatchSpecA, DataPoints], proplist, DataPoints},
        []
    ),
    lists:foreach(fun (Domain) ->
        MatchSpecD = [{{[axb, NodeName, ad, AdapterModule, Domain, '_',      '_', epm], '_', '_'}, [], [true]}],
        MatchSpecI = [{{[axb, NodeName, ad, AdapterModule, Domain, internal, '_', epm], '_', '_'}, [], [true]}],
        MatchSpecE = [{{[axb, NodeName, ad, AdapterModule, Domain, external, '_', epm], '_', '_'}, [], [true]}],
        ok = exometer:ensure(
            [axb, NodeName, ad, AdapterModule, Domain],
            {function, exometer, aggregate, [MatchSpecD, DataPoints], proplist, DataPoints},
            []
        ),
        ok = exometer:ensure(
            [axb, NodeName, ad, AdapterModule, Domain, internal],
            {function, exometer, aggregate, [MatchSpecI, DataPoints], proplist, DataPoints},
            []
        ),
        ok = exometer:ensure(
            [axb, NodeName, ad, AdapterModule, Domain, external],
            {function, exometer, aggregate, [MatchSpecE, DataPoints], proplist, DataPoints},
            []
        )
    end, Domains).


%%
%%  Updates adapter command execution stats.
%%
adapter_command_executed(NodeName, AdapterModule, Domain, Direction, Command, error) ->
    ok = inc_spiral([axb, NodeName, ad, AdapterModule, Domain, Direction, Command, err]),
    ok = inc_day_sl([axb, NodeName, ad, AdapterModule, Domain, Direction, Command, erd]);

adapter_command_executed(NodeName, AdapterModule, Domain, Direction, Command, DurationUS) when is_integer(DurationUS) ->
    ok = inc_spiral([axb, NodeName, ad, AdapterModule, Domain, Direction, Command, epm]),
    ok = inc_day_sl([axb, NodeName, ad, AdapterModule, Domain, Direction, Command, epd]),
    ok = update_spiral([axb, NodeName, ad, AdapterModule, Domain, Direction, Command, dur], DurationUS).


%%
%%  Creates aggregated metrics for the specified flow.
%%
flow_mgr_registered(NodeName, FlowMgrModule, Domains) ->
    DataPoints = [count, one],
    MatchSpecA = [{{[axb, NodeName, fm, FlowMgrModule, '_', '_', epm], '_', '_'}, [], [true]}],
    ok = exometer:ensure(
        [axb, NodeName, fm, FlowMgrModule],
        {function, exometer, aggregate, [MatchSpecA, DataPoints], proplist, DataPoints},
        []
    ),
    lists:foreach(fun (Domain) ->
        MatchSpecD = [{{[axb, NodeName, fm, FlowMgrModule, Domain, '_', epm], '_', '_'}, [], [true]}],
        ok = exometer:ensure(
            [axb, NodeName, fm, FlowMgrModule, Domain],
            {function, exometer, aggregate, [MatchSpecD, DataPoints], proplist, DataPoints},
            []
        )
    end, Domains).


%%
%%
%%
flow_registered(NodeName, FlowMgrModule, Domain, FlowModule) ->
    ok = exometer:ensure([axb, NodeName, fm, FlowMgrModule, Domain, FlowModule, err], spiral,    []),
    ok = exometer:ensure([axb, NodeName, fm, FlowMgrModule, Domain, FlowModule, erd], day_slots, []),
    ok = exometer:ensure([axb, NodeName, fm, FlowMgrModule, Domain, FlowModule, epm], spiral,    []),
    ok = exometer:ensure([axb, NodeName, fm, FlowMgrModule, Domain, FlowModule, epd], day_slots, []),
    ok = exometer:ensure([axb, NodeName, fm, FlowMgrModule, Domain, FlowModule, dur], spiral,    []).


%%
%%
%%
flow_executed(NodeName, FlowMgrModule, Domain, FlowModule, error) ->
    ok = inc_spiral([axb, NodeName, fm, FlowMgrModule, Domain, FlowModule, err]),
    ok = inc_day_sl([axb, NodeName, fm, FlowMgrModule, Domain, FlowModule, erd]);

flow_executed(NodeName, FlowMgrModule, Domain, FlowModule, DurationUS) when is_integer(DurationUS) ->
    ok = inc_spiral([axb, NodeName, fm, FlowMgrModule, Domain, FlowModule, epm]),
    ok = inc_day_sl([axb, NodeName, fm, FlowMgrModule, Domain, FlowModule, epd]),
    ok = update_spiral([axb, NodeName, fm, FlowMgrModule, Domain, FlowModule, dur], DurationUS).


%%
%%
%%
get_flow_value(NodeName, FlowMgrModule, Domain, FlowModule, Type) ->
    get_value_spiral([axb, NodeName, fm, FlowMgrModule, Domain, FlowModule, Type]).


%%
%%
%%
get_adapter_value(NodeName, AdapterModule, Domain, Direction, Command, Type) ->
    get_value_spiral([axb, NodeName, ad, AdapterModule, Domain, Direction, Command, Type]).



%%% ============================================================================
%%% Internal functions.
%%% ============================================================================

%%
%%
%%
inc_spiral(Name) ->
    ok = exometer:update_or_create(Name, 1, spiral, []).


%%
%%
%%
update_spiral(Name, Value) ->
    ok = exometer:update_or_create(Name, Value, spiral, []).


%%
%%
%%
inc_day_sl(Name) ->
    ok = exometer:update_or_create(Name, 1, day_slots, []).


%%
%%
%%
default_value(last) -> undefined;
default_value(_   ) -> 0.


%%
%%
%%
get_optional(Name, DataPoints) when is_list(DataPoints) ->
    case exometer:get_value(Name, DataPoints) of
        {ok, Values}       -> [ Val || {_DP, Val} <- Values ];
        {error, not_found} -> [ default_value(DP) || DP <- DataPoints ]
    end;

get_optional(Name, DataPoint) ->
    case exometer:get_value(Name, DataPoint) of
        {ok, [{DataPoint, Val}]} -> Val;
        {error, not_found} -> default_value(DataPoint)
    end.


%%
%%
%%
get_value_spiral(MatchHead) ->
    Entries = exometer:find_entries(MatchHead),
    lists:foldr(fun({Name, _Type, _Status}, Acc) ->
        Acc + get_optional(Name, one)
    end, 0, Entries).


