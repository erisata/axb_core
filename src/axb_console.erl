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
%%% AxB Console implementation.
%%% Functions in this module are invoked from the shell script.
%%%
-module(axb_console).
-compile([{parse_transform, lager_transform}]).
-export([status/1, stats/1, set_mode/1]).

%%% ============================================================================
%%% Public API.
%%% ============================================================================

%%
%%
%%
status([]) ->
    ok = axb:info(print).


%%
%%
%%
stats([]) ->
    % TODO: Implement.
    ok.


%%
%%
%%
set_mode([_Mode, _Subject]) ->
    % TODO: Implement.
    ok.


