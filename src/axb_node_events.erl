%/--------------------------------------------------------------------
%| Copyright 2015-2016 Erisata, UAB (Ltd.)
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
%%% Event manager for node-related system events.
%%%
-module(axb_node_events).
-behaviour(gen_event).
-compile([{parse_transform, lager_transform}]).
-export([start_spec/0, start_link/0, add_listener/2]).
-export([node_state_changed/2]).
-export([init/1, handle_event/2, handle_call/2, handle_info/2, terminate/2, code_change/3]).
-include("axb.hrl").


%%% ============================================================================
%%% Callback definitions.
%%% ============================================================================

%%
%%  Changes occured with the state the specified node.
%%
-callback handle_node_state_changed(
        Args        :: term(),
        NodeName    :: atom(),
        What        :: term()
    ) ->
        ok |
        {ok, NewArgs :: term()}.



%%% ============================================================================
%%% Public API.
%%% ============================================================================

%%
%%  Returns start spec for a supervisor.
%%
start_spec() ->
    SpecId = ?MODULE,
    StartSpec = {?MODULE, start_link, []},
    {SpecId, StartSpec, permanent, 1000, worker, dynamic}.


%%
%%  Start this event hub.
%%
-spec start_link() -> {ok, pid()} | term().

start_link() ->
    gen_event:start_link({local, ?MODULE}).


%%
%%  Register new listener to receive node events.
%%
-spec add_listener(Module :: module(), Args :: term()) -> ok.

add_listener(Module, Args) ->
    lager:debug("Adding listener, module=~p, args=~p", [Module, Args]),
    ok = gen_event:add_sup_handler(?MODULE, ?MODULE, {Module, Args}).


%%% ============================================================================
%%% Public API: events.
%%% ============================================================================

%%
%%
%%
node_state_changed(NodeName, What) ->
    gen_event:notify(?MODULE, {node_state_changed, NodeName, What}).


%%% ============================================================================
%%% Internal data structures.
%%% ============================================================================

%%
%%  State of the event handler.
%%
-record(state, {
    module  :: module(),
    args    :: term()
}).



%%% ============================================================================
%%% Callbacks for gen_event.
%%% ============================================================================

%%
%%  Initialize the event handler.
%%
init({Module, Args}) ->
    {ok, #state{module = Module, args = Args}}.


%%
%%  Handle events, published in this event hub.
%%
handle_event({node_state_changed, NodeName, What}, State = #state{module = Module, args = Args}) ->
    case Module:handle_node_state_changed(Args, NodeName, What) of
        ok ->
            {ok, State};
        {ok, NewArgs} ->
            {ok, State#state{args = NewArgs}}
    end.


%%
%%  Handle calls addressed to this event handler.
%%
handle_call(_Request, State) ->
    {ok, undefined, State}.


%%
%%  Handle unknown messages.
%%
handle_info(_Info, State) ->
    {ok, State}.


%%
%%  Cleanup.
%%
terminate(_Arg, _State) ->
    ok.


%%
%%  Handle upgrades.
%%
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.



%%% ============================================================================
%%% Internal Functions.
%%% ============================================================================

