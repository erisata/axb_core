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
%%% Node implementation for tests.
%%%
-module(axb_itest_node).
-behaviour(axb_node).
-export([start_spec/0, start_link/1, name/0]).
-export([init/1, code_change/2]).

-define(NAME, axb_itest).

%% =============================================================================
%%  Public API.
%% =============================================================================

%%
%%  Creates supervisor child specification for this module.
%%  TODO: Review.
%%
start_spec() ->
    axb_node:start_spec(?MODULE, {?MODULE, start_link, [esb:name()]}).


%%
%%  Start this module.
%%
start_link(Mode) ->
    axb_node:start_link(?NAME, ?MODULE, Mode, []).


%%
%%  Returns name of this node.
%%
name() ->
    ?NAME.


%% =============================================================================
%%  `eesb_node` callbacks.
%% =============================================================================

%%
%%  Initialize ESB node.
%%
init(empty) ->
    AdaptersToWait = [],
    FlowSupsToWait = [],
    {ok, AdaptersToWait, FlowSupsToWait};

init(adapter) ->
    AdaptersToWait = [axb_itest_adapter],
    FlowSupsToWait = [],
    {ok, AdaptersToWait, FlowSupsToWait}.


%%
%%  Handle code upgrades.
%%
code_change(OldVsn, Extra) ->
    ok.


