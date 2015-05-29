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
%%% TODO: How to get hourly stats?
%%%
-module(axb_stats).
-compile([{parse_transform, lager_transform}]).
-export([
    info/1,
    node_registered/1,
    adapter_registered/3,
    adapter_command_executed/6,
    flow_mgr_registered/3,
    flow_executed/5
]).


%%% ============================================================================
%%% API functions.
%%% ============================================================================

%%
%%
%%
info(list) ->
    Entries = exometer:find_entries([axb]),
    {ok, [ Name || {Name, _Type, enabled} <- Entries ]}.


%%
%%  Creates aggregated metrics for the specified node.
%%
node_registered(NodeName) ->
    DataPoints = [count, one],
    MatchSpecAD = [{{[axb, NodeName, ad, '_', '_', '_', '_', epm], '_', '_'}, [], [true]}],
    MatchSpecFM = [{{[axb, NodeName, fm, '_', '_',      '_', epm], '_', '_'}, [], [true]}],
    ok = exometer:ensure(
        [axb, NodeName, ad],
        {function, exometer, aggregate, [MatchSpecAD, DataPoints], value, DataPoints},
        []
    ),
    ok = exometer:ensure(
        [axb, NodeName, fm],
        {function, exometer, aggregate, [MatchSpecFM, DataPoints], value, DataPoints},
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
        {function, exometer, aggregate, [MatchSpecA, DataPoints], value, DataPoints},
        []
    ),
    lists:foreach(fun (Domain) ->
        MatchSpecD = [{{[axb, NodeName, ad, AdapterModule, Domain, '_',      '_', epm], '_', '_'}, [], [true]}],
        MatchSpecI = [{{[axb, NodeName, ad, AdapterModule, Domain, internal, '_', epm], '_', '_'}, [], [true]}],
        MatchSpecE = [{{[axb, NodeName, ad, AdapterModule, Domain, external, '_', epm], '_', '_'}, [], [true]}],
        ok = exometer:ensure(
            [axb, NodeName, ad, AdapterModule, Domain],
            {function, exometer, aggregate, [MatchSpecD, DataPoints], value, DataPoints},
            []
        ),
        ok = exometer:ensure(
            [axb, NodeName, ad, AdapterModule, Domain, internal],
            {function, exometer, aggregate, [MatchSpecI, DataPoints], value, DataPoints},
            []
        ),
        ok = exometer:ensure(
            [axb, NodeName, ad, AdapterModule, Domain, external],
            {function, exometer, aggregate, [MatchSpecE, DataPoints], value, DataPoints},
            []
        )
    end, Domains).


%%
%%  Updates adapter command execution stats.
%%
adapter_command_executed(NodeName, AdapterModule, Domain, Direction, Command, error) ->
    ok = inc_spiral([axb, NodeName, ad, AdapterModule, Domain, Direction, Command, err]);

adapter_command_executed(NodeName, AdapterModule, Domain, Direction, Command, DurationUS) when is_integer(DurationUS) ->
    ok = inc_spiral([axb, NodeName, ad, AdapterModule, Domain, Direction, Command, epm]),
    ok = upd_duration([axb, NodeName, ad, AdapterModule, Domain, Direction, Command, dur], DurationUS).


%%
%%  Creates aggregated metrics for the specified adapter.
%%
flow_mgr_registered(NodeName, FlowMgrModule, Domains) ->
    DataPoints = [count, one],
    MatchSpecA = [{{[axb, NodeName, fm, FlowMgrModule, '_', '_', epm], '_', '_'}, [], [true]}],
    ok = exometer:ensure(
        [axb, NodeName, fm, FlowMgrModule],
        {function, exometer, aggregate, [MatchSpecA, DataPoints], value, DataPoints},
        []
    ),
    lists:foreach(fun (Domain) ->
        MatchSpecD = [{{[axb, NodeName, fm, FlowMgrModule, Domain, '_', epm], '_', '_'}, [], [true]}],
        ok = exometer:ensure(
            [axb, NodeName, fm, FlowMgrModule, Domain],
            {function, exometer, aggregate, [MatchSpecD, DataPoints], value, DataPoints},
            []
        )
    end, Domains).


%%
%%
%%
flow_executed(NodeName, FlowMgrModule, Domain, FlowModule, error) ->
    ok = inc_spiral([axb, NodeName, fm, FlowMgrModule, Domain, FlowModule, err]);

flow_executed(NodeName, FlowMgrModule, Domain, FlowModule, DurationUS) when is_integer(DurationUS) ->
    ok = inc_spiral([axb, NodeName, fm, FlowMgrModule, Domain, FlowModule, epm]),
    ok = upd_duration([axb, NodeName, fm, FlowMgrModule, Domain, FlowModule, dur], DurationUS).



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
upd_duration(Name, Value) ->
    ok = exometer:update_or_create(Name, Value, duration, []).


