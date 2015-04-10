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
%%% This is a generic behaviour for processing a message in the ESB.
%%%
-module(eesb_flow).
-export([describe/3, default/4, start_link/3, start_link/4]).



-callback handle_describe(
        NodeName    :: term(),
        What        :: start_spec | sup_spec | meta
    ) ->
        {ok, Info :: term()}.


-callback init(
        Args :: term()
    ) ->
        {ok, State :: term()}.


%%
%%
%%
describe(NodeName, FlowModule, What) ->
    case FlowModule:handle_describe(NodeName, What) of
        {ok, Info} ->
            {ok, Info};
        {error, Reason} ->
            {error, Reason}
    end.


%%
%%  Default describe implementation.
%%
default(NodeName, FlowModule, start_spec, _Opts) ->
    SpecId = {?MODULE, NodeName, FlowModule},
    StartSpec = {FlowModule, start_link, []},
    ChildSpec = {SpecId, StartSpec, transient, brutal_kill, worker, [?MODULE, FlowModule]},
    {ok, ChildSpec};

default(NodeName, FlowModule, sup_spec, _Opts) ->
    ChildSpec = eesb_flow_sup_sofo:start_spec(
        {eesb_flow_sup_sofo, NodeName, FlowModule},
        {eesb_flow_sup_sofo, start_link, [NodeName, FlowModule]}
    ),
    {ok, ChildSpec};

default(NodeName, FlowModule, meta, _Opts) ->
    {ok, [
        {node, NodeName},
        {flow, FlowModule}
    ]}.


%%
%%  TODO: Start link.
%%
start_link(Module, Args, Opts) ->
    gen_server:start_link(?MODULE, {Module, Args}, Opts).


%%
%%  TODO: Start link.
%%
start_link(Name, Module, Args, Opts) ->
    gen_server:start_link(Name, ?MODULE, {Module, Args}, Opts).


