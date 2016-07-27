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
%%% This module provides an implementation of the Pipeline EIP.
%%%
%%% TODO: Change it to not use the FSM state timeouts to avoid race conditions.
%%%
-module(axb_eip_pipeline).
-behaviour(axb_flow).
-compile([{parse_transform, lager_transform}]).
-export([start_link/6, respond/1, respond/2, wait_response/2]).
-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3, terminate/3, code_change/4]).
-export([executing/2]).


%%% ============================================================================
%%% Callback definitions.
%%% ============================================================================

%%
%%  Initialize the pipeline process.
%%
-callback init(
        Args        :: term()
    ) ->
        {ok, [Step :: term()], Input :: term()}.

%%
%%  Handle single step.
%%
-callback handle_step(
        StepName    :: term(),
        State       :: term()
    ) ->
        {ok, State :: term()}.



%%% ============================================================================
%%% API functions.
%%% ============================================================================

%%
%%  Start the pipeline.
%%
start_link(NodeName, MgrModule, Domain, Module, Args, Opts) ->
    Noreply = proplists:get_bool(pipeline_noreply, Opts),
    axb_flow:start_link(NodeName, MgrModule, Domain, Module, ?MODULE, {Module, Args, Noreply}, Opts).


%%
%%  Respond to the client in the case of synchronous flow.
%%
respond(Response) ->
    axb_flow:respond(Response).


%%
%%  Respond to the client in the case of synchronous flow.
%%
respond(Client, Response) ->
    axb_flow:respond(Client, Response).


%%
%%  Allows a client to wait for the asynchronous flow response.
%%
wait_response(FlowId, Timeout) ->
    axb_flow:wait_response(FlowId, Timeout).



%%% ============================================================================
%%% Internal state.
%%% ============================================================================

-record(state, {
    module,     % Pipeline implementation process.
    state,      % Current state of the processed data.
    steps,      % Steps, left to process.
    noreply     % If true, reply will not be sent on end (e.g. for async pipelines).
}).


%%% ============================================================================
%%% `axb_flow` callbacks.
%%% ============================================================================

%%
%%  Initialize this process.
%%
init({Module, Args, Noreply}) ->
    case Module:init(Args) of
        {ok, Steps, Input} ->
            StateData = #state{
                module = Module,
                state = Input,
                steps = Steps,
                noreply = Noreply
            },
            {ok, executing, StateData, 0}
    end.



%%
%%  Single state is needed for this process.
%%
executing(timeout, StateData = #state{module = Module, state = State, steps = StepsLeft, noreply = Noreply}) ->
    case StepsLeft of
        [] ->
            case Noreply of
                true  -> ok;
                false -> axb_flow:respond(State)
            end,
            {stop, normal, StateData};
        [Step | OtherSteps] ->
            case Module:handle_step(Step, State) of
                {ok, NewState} ->
                    NewStateData = StateData#state{state = NewState, steps = OtherSteps},
                    {next_state, executing, NewStateData, 0}
            end
    end.


%%
%%  Async all-state events.
%%
handle_event(_Event, StateName, StateData) ->
    {next_state, StateName, StateData}.


%%
%%  Synchronous all-state events.
%%
handle_sync_event(_Event, _From, StateName, StateData) ->
    {reply, undefined, StateName, StateData}.


%%
%%  Unknown messages.
%%
handle_info(_Info, StateName, StateData) ->
    {next_state, StateName, StateData}.


%%
%%  Handle termination.
%%
terminate(_Reason, _StateName, _StateData) ->
    ok.


%%
%%  Code changes are not relevant here?
%%
code_change(_OldVsn, StateName, StateData, _Extra) ->
    {ok, StateName, StateData}.


