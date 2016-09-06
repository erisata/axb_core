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
%%% Exometer metric counting events in fixed day/hour slots.
%%%
-module(axb_stats_day_slots).
-behaviour(exometer_probe).
-compile([{parse_transform, lager_transform}]).
-export([
    register/0
]).
-export([
    behaviour/0,
    probe_init/3,
    probe_terminate/1,
    probe_setopts/3,
    probe_update/2,
    probe_get_value/2,
    probe_get_datapoints/1,
    probe_reset/1,
    probe_sample/1,
    probe_handle_msg/2,
    probe_code_change/3
]).

-define(DATAPOINTS, [last, h0, h1, h2, h3, d0, d1, d2, d3]).
-define(H_SECS, 3600).
-define(D_SECS, 86400).


%%% ============================================================================
%%% Public API.
%%% ============================================================================

register() ->
    true = exometer_admin:set_default(['_'], day_slots, [{module, ?MODULE}]),
    ok.



%%% ============================================================================
%%% Internal data structures.
%%% ============================================================================

-record(state, {
    last,
    ht, h0 = 0, h1 = 0, h2 = 0, h3 = 0,
    dt, d0 = 0, d1 = 0, d2 = 0, d3 = 0
}).



%%% ============================================================================
%%% Callbacks for exometer_probe.
%%% ============================================================================

%%
%%
%%
behaviour() ->
    probe.


%%
%%
%%
probe_init(_Name, day_slots, Options) ->
    ok = exometer_proc:process_options(Options),
    {ok, #state{}}.


%%
%%
%%
probe_terminate(_State) ->
    ok.


%%
%%
%%
probe_setopts(_Entry, _Opts, _State) ->
    ok.


%%
%%
%%
probe_update(Increment, State) ->
    {ok, upd(Increment, State)}.


%%
%%
%%
probe_get_value(DataPoints, State) ->
    {LastBefore, #state{
        h0 = H0, h1 = H1, h2 = H2, h3 = H3,
        d0 = D0, d1 = D1, d2 = D2, d3 = D3
    }} = val(State),
    DPVal = fun
        (last) -> LastBefore;
        (h0  ) -> H0;
        (h1  ) -> H1;
        (h2  ) -> H2;
        (h3  ) -> H3;
        (d0  ) -> D0;
        (d1  ) -> D1;
        (d2  ) -> D2;
        (d3  ) -> D3
    end,
    {ok, lists:map(DPVal, DataPoints)}.


%%
%%
%%
probe_get_datapoints(_State) ->
    {ok, ?DATAPOINTS}.


%%
%%
%%
probe_reset(_State) ->
    {ok, #state{}}.


%%
%%
%%
probe_sample(_State) ->
    {error, unsupported}.

%%
%%
%%
probe_handle_msg(_Message, State) ->
    {ok, State}.


%%
%%
%%
probe_code_change(_OldVsn, State, _Extra) ->
    {ok, State}.



%%% ============================================================================
%%% Internal functions.
%%% ============================================================================

%%
%%
%%
upd(Inc, State) ->
    Now = erlang:system_time(seconds),
    upd_d(Now, Inc, upd_h(Now, Inc, State#state{last = Now})).


%%
%%
%%
val(State = #state{last = Last}) ->
    Now = erlang:system_time(seconds),
    LastBefore = case Last of
        undefined              -> undefined;
        _ when is_number(Last) -> Now - Last
    end,
    {LastBefore, upd_d(Now, 0, upd_h(Now, 0, State))}.


%%
%%
%%
upd_h(Now, Inc, State = #state{ht = undefined}) ->
    HT = Now - Now rem ?H_SECS + ?H_SECS,
    State#state{ht = HT, h0 = Inc, h1 = 0, h2 = 0, h3 = 0};

upd_h(Now, Inc, State = #state{ht = HT, h0 = H0, h1 = H1, h2 = H2}) when Now >= HT ->
    upd_h(Now, Inc, State#state{ht = HT + ?H_SECS, h0 = 0, h1 = H0, h2 = H1, h3 = H2});

upd_h(_Now, Inc, State = #state{h0 = H0}) ->
    State#state{h0 = H0 + Inc}.


%%
%%
%%
upd_d(Now, Inc, State = #state{dt = undefined}) ->
    DT = Now - Now rem ?D_SECS + ?D_SECS,
    State#state{dt = DT, d0 = Inc, d1 = 0, d2 = 0, d3 = 0};

upd_d(Now, Inc, State = #state{dt = DT, d0 = D0, d1 = D1, d2 = D2}) when Now >= DT ->
    upd_d(Now, Inc, State#state{dt = DT + ?D_SECS, d0 = 0, d1 = D0, d2 = D1, d3 = D2});

upd_d(_Now, Inc, State = #state{d0 = D0}) ->
    State#state{d0 = D0 + Inc}.



-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

upd_h_test() ->
    S0 = #state{},
    S1 = #state{ht = 3603600, h0 = 1, h1 = 0, h2 = 0, h3 = 0} = upd_h(3600100, 1, S0),
    S2 = #state{ht = 3603600, h0 = 2, h1 = 0, h2 = 0, h3 = 0} = upd_h(3600200, 1, S1),
         #state{ht = 3607200, h0 = 1, h1 = 2, h2 = 0, h3 = 0} = upd_h(3603700, 1, S2),
    ok.

-endif.


