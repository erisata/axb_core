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
%%%
%%%
-module(eesb_node).
-behaviour(gen_server).
-export([start_spec/2, start_link/4]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).


%% =============================================================================
%%  Callback definitions.
%% =============================================================================

%%
%%
%%
-callback init(Args :: term()) -> ok.


%%
%%
%%
-callback code_change(OldVsn :: term(), Extra :: term()) -> ok.



%% =============================================================================
%% API functions.
%% =============================================================================

%%
%%  Create Supervisor's child spec for starting this node.
%%
start_spec(SpecId, {Module, Function, Args}) when is_atom(Module), is_atom(Function), is_list(Args) ->
    {SpecId,
        {Module, Function, Args},
        permanent,
        brutal_kill,
        supervisor,
        [?MODULE, Module]
    }.


%%
%%
%%
start_link(Name, Module, Args, Opts) ->
    gen_server:start_link(Name, ?MODULE, {Module, Args}, Opts).


%% =============================================================================
%%  Internal state.
%% =============================================================================

-record(state, {
    mod :: module()
}).


%% =============================================================================
%%  Callbacks for gen_server.
%% =============================================================================

%%
%%
%%
init({Module, Args}) ->
    ok = Module:init(Args),
    State = #state{mod = Module},
    {ok, State}.


%%
%%
%%
handle_call(_Request, _From, State) ->
    {reply, undefined, State}.


%%
%%
%%
handle_cast(_Request, State) ->
    {noreply, State}.


%%
%%
%%
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
code_change(OldVsn, State = #state{mod = Module}, Extra) ->
    ok = Module:code_change(OldVsn, Extra), %% TODO: Is this correct?
    {ok, State}.


