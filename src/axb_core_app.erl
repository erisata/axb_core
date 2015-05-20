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

%%
%%  OTP Application module for axb_core.
%%
-module(axb_core_app).
-behaviour(application).
-compile([{parse_transform, lager_transform}]).
-export([start/2, stop/1]).

-define(APP, axb_core).


%% =============================================================================
%%  Public API.
%% =============================================================================


%% =============================================================================
%%  Application callbacks
%% =============================================================================


%%
%% Start the application.
%%
start(_StartType, _StartArgs) ->
    ok = validate_env(application:get_all_env()),
    axb_core_sup:start_link().


%%
%% Stop the application.
%%
stop(_State) ->
    ok.



%% =============================================================================
%%  Helper functions.
%% =============================================================================

%%
%%  Checks if application environment is valid.
%%
validate_env(_Env) ->
    ok.


