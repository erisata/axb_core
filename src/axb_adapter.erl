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
%%% TODO: ESB Adapter behaviour.
%%%
%%% Main functions of this behaviour are the following:
%%%
%%%   * Allow management of services, provided by the adapter (disable temporary, etc.);
%%%   * Collect metrics of the adapter operation;
%%%   * Define metadata, describing the adapter.
%%%
%%% TODO: Rewrite.
%%% This behaviour is implemented not using a dedicated process,
%%% in order to avoid bootleneck when processing adapter commands.
%%% This also allows to have any structure for the particular adapter,
%%% in terms of processes and supervision tree.
%%%
-module(axb_adapter).
-behaviour(gen_server).
-compile([{parse_transform, lager_transform}]).
-export([start_link/4, set_mode/5]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-define(REF(NodeName, AdapterModule), {via, gproc, {n, l, {?MODULE, NodeName, AdapterModule}}}).

%%% =============================================================================
%%% Callback definitions.
%%% =============================================================================

%%
%%  This callback should return services, provided by this adapter.
%%
-callback provided_services(
        Args :: term()
    ) ->
        {ok, [{ServiceName :: term(), ServiceModule :: module()}]}.

% % % %%
% % % %%
% % % %%
% % % -callback handle_describe(
% % %         NodeName    :: term(),
% % %         What        :: start_spec | sup_spec | meta
% % %     ) ->
% % %         {ok, Info :: term()}.
% % %
% % %
% % % %%
% % % %%
% % % %%
% % % -callback handle_mode_change(
% % %         NodeName        :: atom(),
% % %         AdapterModule   :: module(),
% % %         Services        :: [Service :: atom()] | all,
% % %         Mode            :: online | offline,
% % %         Direction       :: internal | external | all
% % %     ) ->
% % %         ok.

%%% =============================================================================
%%% Public API.
%%% =============================================================================

%%
%%  Start the adapter.
%%
start_link(NodeName, Module, Args, Opts) ->
    gen_server:start_link(?REF(NodeName, Module), ?MODULE, {NodeName, Module, Args}, Opts).


%%
%%
%%
-spec set_mode(
        NodeName        :: atom(),
        AdapterModule   :: module(),
        Services        :: [Service :: atom()] | all,
        Mode            :: online | offline,
        Direction       :: internal | external | all
    ) ->
        ok.

set_mode(NodeName, AdapterModule, Services, Mode, Direction) ->
    ok.


%%% =============================================================================
%%% Internal state.
%%% =============================================================================

-record(service, {
    name    :: term(),
    module  :: module(),
    online  :: none | external | internal | both
}).
-record(state, {
    node        :: atom(),
    module      :: module(),
    args        :: term(),
    services    :: [#service{}]
}).


%%% =============================================================================
%%% Callbacks for `gen_server`.
%%% =============================================================================

%%
%%
%%
init({NodeName, Module, Args}) ->
    case Module:provided_services(Args) of
        {ok, Services} ->
            State = #state{
                node     = NodeName,
                module   = Module,
                args     = Args,
                services = [ #service{name = N, module = M, online = none} || {N, M} <- Services ]
            },
            ok = axb_node:register_adapter(NodeName, Module, []),
            {ok, State}
    end.


%%
%%
%%
handle_call(_Message, _From, State) ->
    {reply, undefined, State}.


%%
%%
%%
handle_cast(Message, State) ->
    {noreply, State}.


%%
%%
%%
handle_info(Message, State) ->
    {noreply, State}.


%%
%%
%%
terminate(_Reason, _State) ->
    ok.

%%
%%
%%
code_change(OldVsn, State, Extra) ->
    {ok, State}.


