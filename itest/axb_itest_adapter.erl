%/--------------------------------------------------------------------
%| Copyright 2013-2015 Erisata, UAB (Ltd.)
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
%%% Adapter implementation for tests.
%%% This module is not a process.
%%%
-module(axb_itest_adapter).
-behaviour(axb_adapter).
-compile([{parse_transform, lager_transform}]).
-export([start_link/1, send_message/1, message_received/1]).
-export([provided_services/1, service_changed/3]).


%%% =============================================================================
%%% API functions.
%%% =============================================================================

%%
%%
%%
start_link(Mode) ->
    axb_adapter:start_link(axb_itest_node:name(), ?MODULE, Mode, []).


%%
%%  Business-specific function.
%%
send_message(SomeArg) ->
    axb_adapter:command(axb_itest_node:name(), ?MODULE, main, internal, send_message, fun () ->
        {ok, SomeArg}
    end).

%%
%%  Business-specific function.
%%
message_received(SomeArg) ->
    axb_adapter:command(axb_itest_node:name(), ?MODULE, main, external, message_received, fun () ->
        {ok, SomeArg}
    end).



%%% =============================================================================
%%% Callbacks for `axb_adapter`.
%%% =============================================================================

%%
%%  Returns a list of services, provided by this adapter.
%%
provided_services(empty) ->
    {ok, []};

provided_services(single) ->
    {ok, [main]}.

%%
%%  Receives notification on a service state change.
%%
service_changed(_ServiceName, _Direction, _Online) ->
    ok.
