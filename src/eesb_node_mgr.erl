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
%%% Maintains a list of known nodes.
%%%
-module(eesb_node_mgr).
-behaviour(gen_server).
-export([start_spec/0, start_link/0]).
-export([register_node/2, unregister_node/1, register_flow/3, unregister_flow/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).


%% =============================================================================
%% API functions.
%% =============================================================================

%%
%%
%%
start_spec() ->
    SpecId = ?MODULE,
    StartSpec = {?MODULE, start_link, []},
    {SpecId, StartSpec, permanent, brutal_kill, worker, [?MODULE]}.


%%
%%
%%
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, {}, []).


%%
%%  Registers and links with the node.
%%
register_node(NodeName, Opts) ->
    NodePid = self(),
    gen_server:call(?MODULE, {register_node, NodeName, NodePid, Opts}).


%%
%%  Unlinks and unregisters the node.
%%
unregister_node(NodeName) ->
    gen_server:call(?MODULE, {unregister_node, NodeName}).


%%
%%  Register a flow for the node.
%%
register_flow(NodeName, FlowModule, Opts) ->
    gen_server:call(?MODULE, {register_flow, NodeName, FlowModule, Opts}).


%%
%%  Unregisters the flow for the node..
%%
unregister_flow(NodeName, FlowModule) ->
    gen_server:call(?MODULE, {unregister_flow, NodeName, FlowModule}).



% %%
% %%  TODO: ...
% %%
% register_adapter() ->
%     ok.
%
%
% %%
% %%  TODO: ...
% %%
% unregister_adapter() ->
%     ok.
%
%
%
% %%
% %%  TODO: ...
% %%
% register_endpoint() ->
%     ok.
%
%
% %%
% %%  TODO: ...
% %%
% unregister_endpoint() ->
%     ok.



%% =============================================================================
%%  Internal state.
%% =============================================================================

-record(node, {
    name        :: term(),      %%  Node name.
    pid         :: pid(),       %%  Node process PID.
    flows       :: [module()]   %%  Registered flow modules.
}).

-record(state, {
    nodes :: [#node{}]
}).



%% =============================================================================
%%  Callbacks for `gen_server`.
%% =============================================================================

%%
%%
%%
init({}) ->
    erlang:process_flag(trap_exit, true),
    State = #state{
        nodes = []
    },
    {ok, State}.


%%
%%
%%
handle_call({register_node, NodeName, NodePid, _Opts}, _From, State = #state{nodes = Nodes}) ->
    case lists:keyfind(NodeName, #node.name, Nodes) of
        false ->
            true = erlang:link(NodePid),
            Node = #node{
                name     = NodeName,
                pid      = NodePid,
                flows    = []
            },
            {reply, ok, State#state{nodes = [Node | Nodes]}};
        #node{} ->
            Reason = {node_already_registered, NodeName, NodePid},
            {reply, {error, Reason}, State}
    end;

handle_call({unregister_node, NodeName}, _From, State = #state{nodes = Nodes}) ->
    NewNodes = case lists:keytake(NodeName, #node.name, Nodes) of
        false ->
            Nodes;
        {value, #node{pid = NodePid, flows = Flows}, OtherNodes} ->
            UnregisterFlowFun = fun (FlowModule) ->
                case eesb_flow_sup:unregister_flow(NodeName, FlowModule) of
                    ok -> ok;
                    {error, _Reason} -> ok
                end
            end,
            ok = lists:foreach(UnregisterFlowFun, Flows),
            true = erlang:unlink(NodePid),
            OtherNodes
    end,
    {reply, ok, State#state{nodes = NewNodes}};

handle_call({register_flow, NodeName, FlowModule, _Opts}, _From, State = #state{nodes = Nodes}) ->
    case lists:keyfind(NodeName, #node.name, Nodes) of
        false ->
            Reason = {node_not_registered, NodeName},
            {reply, {error, Reason}, State};
        Node = #node{flows = Flows} ->
            case lists:member(FlowModule, Flows) of
                true ->
                    {reply, ok, State};
                false ->
                    case eesb_flow_sup:register_flow(NodeName, FlowModule) of
                        ok ->
                            NewNode = Node#node{flows = [FlowModule | Flows]},
                            NewNodes = lists:keyreplace(NodeName, #node.name, Nodes, NewNode),
                            {reply, ok, State#state{nodes = NewNodes}};
                        {error, Reason} ->
                            {reply, {error, Reason}, State}
                    end
            end
    end;

handle_call({unregister_flow, NodeName, FlowModule}, _From, State = #state{nodes = Nodes}) ->
    case lists:keyfind(NodeName, #node.name, Nodes) of
        false ->
            Reason = {node_not_registered, NodeName},
            {reply, {error, Reason}, State};
        Node = #node{flows = Flows} ->
            case lists:member(FlowModule, Flows) of
                true ->
                    UnregResult = case eesb_flow_sup:unregister_flow(NodeName, FlowModule) of
                        ok                   -> ok;
                        {error, not_found}   -> ok;
                        {error, UnregReason} -> {error, UnregReason}
                    end,
                    case UnregResult of
                        ok ->
                            NewNode = Node#node{flows = lists:delete(FlowModule, Flows)},
                            NewNodes = lists:keyreplace(NodeName, #node.name, Nodes, NewNode),
                            {reply, ok, State#state{nodes = NewNodes}};
                        {error, Reason} ->
                            {reply, {error, Reason}, State}
                    end;
                false ->
                    {reply, ok, State}
            end
    end.

%%
%%
%%
handle_cast(_Request, State) ->
    {noreply, State}.


%%
%%
%%
handle_info({'EXIT', From, _Reason}, State = #state{nodes = Nodes}) ->
    NewNodes = case lists:keytake(From, #node.pid, Nodes) of
        false -> Nodes;
        {value, _Node, OtherNodes} -> OtherNodes
    end,
    {noreply, State#state{nodes = NewNodes}};

handle_info(_Request, State) ->
    {noreply, State}.

%%
%%
%%
terminate(_Reason, _State) ->
    ok.


%%
%%
%%
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.



%% =============================================================================
%%  Internal functions.
%% =============================================================================


