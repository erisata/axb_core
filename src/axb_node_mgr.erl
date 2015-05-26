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
-module(axb_node_mgr).
-behaviour(gen_server).
-compile([{parse_transform, lager_transform}]).
-export([start_spec/0, start_link/0]).
-export([register_node/2, unregister_node/1, registered_nodes/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).


%%% ============================================================================
%%% API functions.
%%% ============================================================================

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
%%  Returns a list of registered nodes.
%%
registered_nodes() ->
    gen_server:call(?MODULE, registered_nodes).



%%% ============================================================================
%%% Internal state.
%%% ============================================================================

-record(node, {
    name        :: term(),      %%  Node name.
    pid         :: pid()        %%  Node process PID.
}).

-record(state, {
    nodes :: [#node{}]
}).



%%% ============================================================================
%%% Callbacks for `gen_server`.
%%% ============================================================================

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
                name = NodeName,
                pid  = NodePid
            },
            lager:info("Node ~p registered, pid=~p", [NodeName, NodePid]),
            {reply, ok, State#state{nodes = [Node | Nodes]}};
        #node{pid = NodePid} ->
            lager:warning("Node ~p already registered with the same pid=~p", [NodeName, NodePid]),
            {reply, ok, State};
        #node{pid = OldPid} ->
            lager:warning("Node ~p already registered, newPid=~p, oldPid=~p", [NodeName, NodePid, OldPid]),
            Reason = {node_already_registered, NodeName, NodePid},
            {reply, {error, Reason}, State}
    end;

handle_call({unregister_node, NodeName}, _From, State = #state{nodes = Nodes}) ->
    NewNodes = case lists:keytake(NodeName, #node.name, Nodes) of
        false ->
            lager:warning("Node ~p is unknown, unable to unregister it.", [NodeName]),
            Nodes;
        {value, #node{pid = NodePid}, OtherNodes} ->
            true = erlang:unlink(NodePid),
            lager:info("Node ~p unregistered by request, pid=~p", [NodeName, NodePid]),
            OtherNodes
    end,
    {reply, ok, State#state{nodes = NewNodes}};

handle_call(registered_nodes, _From, State = #state{nodes = Nodes}) ->
    NodeNames = [ N || #node{name = N} <- Nodes ],
    {reply, {ok, NodeNames}, State}.


%%
%%
%%
handle_cast(_Request, State) ->
    {noreply, State}.


%%
%%
%%
handle_info({'EXIT', From, Reason}, State = #state{nodes = Nodes}) ->
    case lists:keytake(From, #node.pid, Nodes) of
        false ->
            {stop, Reason, State};
        {value, #node{name = NodeName}, OtherNodes} ->
            lager:warning("Node ~p unregistered, because it died, pid=~p, reason=~p.", [NodeName, From, Reason]),
            {noreply, State#state{nodes = OtherNodes}}
    end;

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



%%% ============================================================================
%%% Internal functions.
%%% ============================================================================


