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
-export([register_node/2, unregister_node/1, register_flow/3, unregister_flow/2]).


%%
%%  Register and links the node.
%%  Should be called from the node process.
%%
register_node(NodeName, Opts) ->
    axb_node_mgr:register_node(NodeName, Opts).


%%
%%  Unlinks and unregisters the node.
%%
unregister_node(NodeName) ->
    axb_node_mgr:unregister_node(NodeName).


%%
%%  Returns AxB state:
%%
%%    * Nodes
%%    * Node adapters, flow supervisors, flows types.
%%
info() ->   % TODO
    ok.


