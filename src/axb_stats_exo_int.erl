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
%%% Exometer metric counting events in fixed intervals.
%%%
%%% TODO: Decide, how to store the data. It should be read and saved
%%%     on each update. Maybe it should be implemented as a probe.
%%%
-module(axb_stats_exo_int).
-behaviour(exometer_entry).
-compile([{parse_transform, lager_transform}]).
-export([behaviour/0, new/3, delete/3, get_value/4, update/4, reset/3, sample/3, get_datapoints/3, setopts/3]).

-define(H_SECS, 3600).
-define(D_SECS, 86400).


%%% ============================================================================
%%% Internal data structures.
%%% ============================================================================

-record(st, {
    last,
    ht, h0, h1, h2, h3,
    dt, d0, d1, d2, d3
}).



%%% ============================================================================
%%% Callbacks for exometer_entry.
%%% ============================================================================

%%
%%
%%
behaviour() ->
    entry.


%%
%%
%%
new(_Name, _Type, _Opts) ->
    ok.


%%
%%
%%
delete(_Name, _Type, _Ref) ->
    ok.


%%
%%
%%
get_value(_Name, _Type, _Ref, _DataPoints) ->
    [
        {this, todo},
        {prev, todo},
        {last, todo}
    ].


%%
%%
%%
update(_Name, _Value, _Type, _Ref) ->
    ok.


%%
%%
%%
reset(_Name, _Type, _Ref) ->
    ok.


%%
%%
%%
sample(_Name, _Type, _Ref) ->
    ok.


%%
%%
%%
get_datapoints(_Name, interval, _Ref) ->
    [this, prev, last].


%%
%%
%%
setopts(_Entry, _Options, _Status) ->
    ok.



%%% ============================================================================
%%% Internal functions.
%%% ============================================================================

%%
%%
%%
upd(N, St) ->
    Now = erlang:system_time(seconds),
    upd_d(Now, N, upd_h(Now, N, St#st{last = Now})).


%%
%%
%%
val(St) ->
    Now = erlang:system_time(seconds),
    #st{
        last = Last,
        h0 = H0, h1 = H1, h2 = H2, h3 = H3,
        d0 = D0, d1 = D1, d2 = D2, d3 = D3
    } = upd_d(Now, 0, upd_h(Now, 0, St)),
    [
        {last, Last},
        {h0,   H0},
        {h1,   H1},
        {h2,   H2},
        {h3,   H3},
        {d0,   D0},
        {d1,   D1},
        {d2,   D2},
        {d3,   D3}
    ].


%%
%%
%%
upd_h(Now, N, St = #st{ht = unefined}) ->
    HT = Now - Now rem ?H_SECS,
    St#st{ht = HT, h0 = N, h1 = 0, h2 = 0, h3 = 0};

upd_h(Now, N, St = #st{ht = HT, h0 = H0, h1 = H1, h2 = H2}) when Now >= HT ->
    upd_h(Now, N, St#st{ht = HT + ?H_SECS, h0 = 0, h1 = H0, h2 = H1, h3 = H2});

upd_h(_Now, N, St = #st{h0 = H0}) ->
    St#st{h0 = H0 + N}.


%%
%%
%%
upd_d(Now, N, St = #st{dt = unefined}) ->
    DT = Now - Now rem ?D_SECS,
    St#st{dt = DT, d0 = N, d1 = 0, d2 = 0, d3 = 0};

upd_d(Now, N, St = #st{dt = DT, d0 = D0, d1 = D1, d2 = D2}) when Now >= DT ->
    upd_d(Now, N, St#st{dt = DT + ?D_SECS, d0 = 0, d1 = D0, d2 = D1, d3 = D2});

upd_d(_Now, N, St = #st{d0 = D0}) ->
    St#st{d0 = D0 + N}.


