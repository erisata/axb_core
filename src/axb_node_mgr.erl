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
-export([register_node/2, unregister_node/1, info/1]).
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
    {SpecId, StartSpec, permanent, 1000, worker, [?MODULE]}.


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
info(What) ->
    gen_server:call(?MODULE, {info, What}).



%%% ============================================================================
%%% Internal state.
%%% ============================================================================

-record(node, {
    name        :: term(),              %%  Node name.
    pid         :: pid() | undefined,   %%  Node process PID.
    reg_count   :: integer(),           %%  Number of times the node was registered (probably restarted).
    known_from  :: os:timestamp(),      %%  Time of the first node registration.
    start_time  :: os:timestamp(),      %%  Time of the last node registration.
    term_time   :: os:timestamp()       %%  Time of the last exit, if the node is down.
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
    Now = os:timestamp(),
    case lists:keyfind(NodeName, #node.name, Nodes) of
        false ->
            true = erlang:link(NodePid),
            Node = #node{
                name = NodeName,
                pid = NodePid,
                reg_count = 1,
                known_from = Now,
                start_time = Now,
                term_time = undefined
            },
            lager:info("Node ~p registered, pid=~p", [NodeName, NodePid]),
            {reply, ok, State#state{nodes = [Node | Nodes]}};
        #node{pid = OldPid} when OldPid =:= NodePid ->
            lager:warning("Node ~p already registered with the same pid=~p", [NodeName, NodePid]),
            {reply, ok, State};
        #node{pid = undefined, reg_count = RegCount} = Node ->
            true = erlang:link(NodePid),
            NewNode = Node#node{
                pid = NodePid,
                reg_count = RegCount + 1,
                start_time = Now,
                term_time = undefined
            },
            NewNodes = lists:keyreplace(NodeName, #node.name, Nodes, NewNode),
            lager:info("Node ~p re-registered, pid=~p", [NodeName, NodePid]),
            {reply, ok, State#state{nodes = NewNodes}};
        #node{pid = OldPid} when OldPid =/= NodePid ->
            lager:warning("Node ~p already registered, newPid=~p, oldPid=~p", [NodeName, NodePid, OldPid]),
            Reason = {node_already_registered, OldPid},
            {reply, {error, Reason}, State}
    end;

handle_call({unregister_node, NodeName}, _From, State = #state{nodes = Nodes}) ->
    NewNodes = case lists:keytake(NodeName, #node.name, Nodes) of
        false ->
            lager:warning("Node ~p is unknown, unable to unregister it.", [NodeName]),
            Nodes;
        {value, #node{pid = NodePid}, OtherNodes} ->
            true = erlang:unlink(NodePid),
            lager:info("Node ~p unregistered, pid=~p", [NodeName, NodePid]),
            OtherNodes
    end,
    {reply, ok, State#state{nodes = NewNodes}};

handle_call({info, What}, _From, State = #state{nodes = Nodes}) ->
    case What of
        list ->
            List = [ Name || #node{name = Name} <- Nodes ],
            {reply, {ok, List}, State};
        status ->
            List = [ {Name, node_status(Node)} || Node = #node{name = Name} <- Nodes ],
            {reply, {ok, List}, State};
        details ->
            List = [
                {Name, [
                    {status, node_status(Node)}
                ]}
                || Node = #node{name = Name} <- Nodes
            ],
            {reply, {ok, List}, State}
    end.


%%
%%
%%
handle_cast(_Request, State) ->
    {noreply, State}.


%%
%%
%%
handle_info({'EXIT', From, Reason}, State = #state{nodes = Nodes}) ->
    case lists:keyfind(From, #node.pid, Nodes) of
        false ->
            lager:warning("Linked process ~p died, reason=~p.", [From, Reason]),
            {stop, Reason, State};
        Node = #node{name = NodeName} ->
            Now = os:timestamp(),
            NewNode = Node#node{pid = undefined, term_time = Now},
            NewNodes = lists:keyreplace(NodeName, #node.name, Nodes, NewNode),
            lager:warning("Node ~p died, pid=~p, reason=~p.", [NodeName, From, Reason]),
            {noreply, State#state{nodes = NewNodes}}
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

%%
%%  Determine adapter's status.
%%
node_status(#node{pid = undefined})            -> down;
node_status(#node{pid = Pid}) when is_pid(Pid) -> running.


