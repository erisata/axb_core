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
%%% The context links all the parts in the AXB, where particular message
%%% is processed. It is used for tracing message processing, corelating
%%% log messages, etc. By defauls, context automatically include all the
%%% flows and adapters, involved in processing particular message.
%%%
%%% Context information is bound to the process, therefore it must be
%%% propagated explicitly, if some messages are processed in other
%%% processes than flows and adapter processes.
%%%
%%% This module also makes the context ID available for the lager logger,
%%% with the name `ctx`.
%%%
-module(axb_context).
-compile([{parse_transform, lager_transform}]).
-export([setup/1, ensure/0, cleanup/0, id/0, push/0, pop/1]).

-define(CTX_PDICT, 'axb_context$id').
-define(CTX_LAGER, 'ctx').


%%% ============================================================================
%%% Public API.
%%% ============================================================================

%%
%%  Define context for the current process.
%%
-spec setup(CtxId :: term() | undefined) -> term().

setup(undefined) ->
    NewCtxId = axb:make_id(),
    lager:debug("New context defined ~p", [NewCtxId]),	% TODO: Do not log it, or log it after the context is defined.
    setup(NewCtxId);

setup(CtxId) ->
    OldCtxId = erlang:put(?CTX_PDICT, CtxId),
    case OldCtxId of
        undefined ->
            ok = lager:md(lists:keystore(?CTX_LAGER, 1, lager:md(), {?CTX_LAGER, CtxId}));
        CtxId ->
            ok;
        _ ->
            ok = lager:md(lists:keystore(?CTX_LAGER, 1, lager:md(), {?CTX_LAGER, CtxId})),
            lager:debug("Existing context ~p redefined to ~p", [OldCtxId, CtxId])
    end,
    CtxId.


%%
%%  Ensure, that the context is defined for the current process.
%%  It will keep existing context, if it is present, or will define new one.
%%
-spec ensure() -> term().

ensure() ->
    setup(id()).


%%
%%  Forget the context information for the current process.
%%
-spec cleanup() -> ok.

cleanup() ->
    ok = lager:md(lists:keydelete(?CTX_LAGER, 1, lager:md())),
    _ = erlang:erase(?CTX_PDICT),
    ok.


%%
%%  Returns current context id or `undefined`, if the context is not defined.
%%
-spec id() -> undefined | term().

id() ->
    erlang:get(?CTX_PDICT).


%%
%%  Ensure, that the context is defined for the current process, and
%%  returns a reference to the previous context state.
%%
-spec push() -> {ok, CtxRef :: term()}.

push() ->
    OldCtxId = id(),
    _ = setup(OldCtxId),
    {ok, OldCtxId}.

%%
%%
%%
-spec pop(CtxRef :: term()) -> ok.

pop(undefined) ->
    cleanup();

pop(PrevCtx) ->
    _ = setup(PrevCtx),
    ok.


