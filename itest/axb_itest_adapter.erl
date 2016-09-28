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
-export([start_link/1, start_link/2, send_message/1, message_received/2, test_crash/0, test_context_ext/0, test_context_int/0]).
-export([init/1, domain_change/4, code_change/3]).


%%% =============================================================================
%%% API functions.
%%% =============================================================================

%%
%%  Adapters can be started anonymous. In that case you can access them
%%  by using PID or {via, axb, {adapter, NodeName, AdapterName}}.
%%
start_link(Mode) ->
    NodeName = axb_itest_node:name(),
    AdapterName = ?MODULE,
    AdapterCBMod = ?MODULE,
    AdapterArg = Mode,
    axb_adapter:start_link(NodeName, AdapterName, AdapterCBMod, AdapterArg, []).

%%
%%  Adapters can be registered explicitly. In that case, they will be accessible
%%  by several registrations (the explicit one, and the {via, axb, ...}).
%%
start_link(AdapterName, Mode) ->
    axb_adapter:start_link({local, AdapterName}, axb_itest_node:name(), AdapterName, ?MODULE, Mode, []).


%%
%%  Business-specific function.
%%
send_message(Message) ->
    axb_adapter:command(axb_itest_node:name(), ?MODULE, main, internal, send_message, fun () ->
        {ok, Message}
    end).

%%
%%  Business-specific function.
%%
message_received(Message, _Sender) ->
    axb_adapter:command(axb_itest_node:name(), ?MODULE, main, external, message_received, fun () ->
        {ok, Message}
    end).


%%
%%  Check, if crash is handled properly.
%%
test_crash() ->
    axb_adapter:command(axb_itest_node:name(), ?MODULE, main, internal, test_crash, fun () ->
        ok = os:timestamp()
    end).


%%
%% Call flow within own context.
%%
test_context_ext() ->
    axb_adapter:command(axb_itest_node:name(), ?MODULE, main, external, test_context_ext, fun () ->
        CtxId1 = axb_context:id(),
        {ok, CtxId2, CtxId3} = axb_itest_flow:test_context_adapter(),
        {ok, CtxId1, CtxId2, CtxId3}
    end).


%%
%%  This is called from the flow.
%%
test_context_int() ->
    axb_adapter:command(axb_itest_node:name(), ?MODULE, main, internal, test_context_int, fun () ->
        CtxId = axb_context:id(),
        {ok, CtxId}
    end).



%%% =============================================================================
%%% Internal data structures.
%%% =============================================================================

-record(state, {
    arg :: term()
}).



%%% =============================================================================
%%% Callbacks for `axb_adapter`.
%%% =============================================================================

%%
%%
%%
init(empty) ->
    {ok, #{domains => #{}}, #state{arg = empty}};

init(single) ->
    AdapterSpec = #{
        description => "Single-domain adapter.",
        domains => #{
            main => #{
                test_crash => internal
            }
        }
    },
    {ok, AdapterSpec, #state{arg = single}};

init(Arg) ->
    AdapterSpec = #{
        description => "This is my test adapter. It is used to do good things :)",
        domains => #{
            main => #{
                test_crash => internal
            },
            context => #{
                test_context_int => #{direction => internal},
                test_context_ext => #{direction => external}
            },
            message => #{
                send_message     => #{direction => internal, user_args => ["some_message"]},
                message_received => #{direction => external, user_args => [<<"message">>, sender]}
            }
        }
    },
    {ok, AdapterSpec, #state{arg = Arg}}.


%%
%%  Receives notification on a domain state change.
%%
domain_change(_ServiceName, _Direction, _Online, State) ->
    {ok, State}.


%%
%%
%%
code_change(AdapterSpec, State, _Extra) ->
    {ok, AdapterSpec, State}.


