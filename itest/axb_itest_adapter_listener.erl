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
%%% Simple gen server, for testing supervisor.
%%%
-module(axb_itest_adapter_listener).
-behaviour(gen_server).
-compile([{parse_transform, lager_transform}]).
-export([start_link/0, is_online/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).


%%% ============================================================================
%%% API functions.
%%% ============================================================================

%%
%%
%%
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, {}, []).


%%
%%
%%
is_online() ->
    Pid = erlang:whereis(?MODULE),
    is_pid(Pid).



%%% ============================================================================
%%% Internal state.
%%% ============================================================================

-record(state, {
}).



%%% ============================================================================
%%% Callbacks for `gen_server`.
%%% ============================================================================

%%
%%
%%
init({}) ->
    {ok, #state{}}.


%%
%%
%%
handle_call(_Request, _From, State) ->
    {reply, ok, State}.


%%
%%
%%
handle_cast(_Message, State) ->
    {noreply, State}.


%%
%%
%%
handle_info(_Info, State) ->
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

