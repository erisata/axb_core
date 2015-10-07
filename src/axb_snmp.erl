%%%
%%% Implementation of the SNMP metrics, as described in the `mibs/ERISATA-AXB-MIB.mib`.
%%%
-module(axb_snmp).
-export([
    ot_flows_executed/1,
    ot_flows_duration/1,
    ot_flows_errors/1,
    ot_adapters_executed/1,
    ot_adapters_duration/1,
    ot_adapters_errors/1
]).

-define(ANY, '_').

%%
%%
%%
ot_flows_executed(get) ->
    {value, axb_stats:get_flow_value(?ANY, ?ANY, ?ANY, ?ANY, epm)}.


%%
%%
%%
ot_flows_duration(get) ->
    {value, axb_stats:get_flow_value(?ANY, ?ANY, ?ANY, ?ANY, dur)}.


%%
%%
%%
ot_flows_errors(get) ->
    {value, axb_stats:get_flow_value(?ANY, ?ANY, ?ANY, ?ANY, err)}.


%%
%%
%%
ot_adapters_executed(get) ->
    {value, axb_stats:get_adapter_value(?ANY, ?ANY, ?ANY, ?ANY, ?ANY, epm)}.


%%
%%
%%
ot_adapters_duration(get) ->
    {value, axb_stats:get_adapter_value(?ANY, ?ANY, ?ANY, ?ANY, ?ANY, dur)}.


%%
%%
%%
ot_adapters_errors(get) ->
    {value, axb_stats:get_adapter_value(?ANY, ?ANY, ?ANY, ?ANY, ?ANY, err)}.


