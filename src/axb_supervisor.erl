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
%%% A supervisor that handles starting and stopping child processes
%%% more conveniently. This supervisor should be useful for implementing
%%% adapters, when some processes should be started/stopped depending
%%% on the adapter's operation mode.
%%%
-module(axb_supervisor).
-compile([{parse_transform, lager_transform}]).
% TODO: All
% -init(Args :: term()) -> {ok, SupSpec :: term()} | ignore.
%
%
% %%
% %%
% %%
% start_link() ->
%     supervisor:start_link().
%
%
% %%
% %%
% %%
% start_child() ->
%     ok.
%
%
% %%
% %%
% %%
% stop_child() ->
%     ok.
%
%



% %%
% register_flow(NodeName, FlowModule) ->
%     case axb_flow:describe(NodeName, FlowModule, sup_spec) of
%         undefined ->
%             ok;
%         {ok, ChildSpec} ->
%             {ok, _ChildPid} = supervisor:start_child(?REF(NodeName), ChildSpec),
%             ok
%     end.
%
%
% %%
% %%
% %%
% unregister_flow(NodeName, FlowModule) ->
%     case supervisor:terminate_child(?REF(NodeName), FlowModule) of
%         ok ->
%             ok = supervisor:delete_child(?REF(NodeName), FlowModule),
%             ok;
%         {error, not_found} ->
%             {error, not_found}
%     end.
