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

%%
%%  Entry point for starting AxB Core for interactive tests.
%%
-module(axb_core_RTEST).
-compile([{parse_transform, lager_transform}]).
-behaviour(supervisor).
-export([start/0]).
-export([init/1]).


%%
%%  This function is called from the command line.
%%
start() ->
    {ok, Pid} = supervisor:start_link({local, ?MODULE}, ?MODULE, {}),
    true = erlang:unlink(Pid),
    ok.


%%
%%  Callback for the `supervisor`.
%%
init({}) ->
    {ok, {{one_for_all, 100, 10}, [
        {axb_itest_node,
            {axb_itest_node, start_link, [both]},
            permanent, brutal_kill, worker,
            [axb_node, axb_itest_node]
        },
        {axb_itest_flows,
            {axb_itest_flows, start_link, [single]},
            permanent, brutal_kill, supervisor,
            [axb_flow_mgr, axb_itest_flows]
        },
        {axb_itest_adapter,
            {axb_itest_adapter, start_link, [single]},
            permanent, brutal_kill, worker,
            [axb_adapter, axb_itest_adapter]
        }
    ]}}.


