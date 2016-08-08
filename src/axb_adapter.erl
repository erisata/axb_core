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
%%% ESB Adapter behaviour.
%%%
%%% Main functions of this behaviour are the following:
%%%
%%%   * Allow management of domains, provided by the adapter (disable temporary, etc.);
%%%   * Collect metrics of the adapter operation;
%%%   * Define metadata, describing the adapter.
%%%
%%% TODO: Add support for admin actions - predefined commands invokations.
%%%
-module(axb_adapter).
-behaviour(gen_server).
-compile([{parse_transform, lager_transform}]).
-export([start_link/4, info/3, domain_online/5, command/6]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-define(REG(NodeName, Module), {n, l, {?MODULE, NodeName, Module}}).
-define(REF(NodeName, Module), {via, gproc, ?REG(NodeName, Module)}).


%%% =============================================================================
%%% Callback definitions.
%%% =============================================================================

%%
%%  This callback should return domains, provided by this adapter.
%%
-callback provided_domains(
        Args :: term()
    ) ->
        {ok, [DomainName :: atom()]}.


%%
%%  This callback notifies the adapter about changed domain states.
%%
-callback domain_changed(
        DomainName  :: atom(),
        Direction   :: internal | external,
        Online      :: boolean()
    ) ->
        ok.


%%% =============================================================================
%%% Internal state.
%%% =============================================================================

-record(domain, {
    name        :: term(),
    internal    :: boolean(),
    external    :: boolean()
}).

-record(state, {
    node        :: atom(),
    module      :: module(),
    args        :: term(),
    domains     :: [#domain{}]
}).



%%% =============================================================================
%%% Public API.
%%% =============================================================================

%%
%%  Start the adapter.
%%
start_link(NodeName, Module, Args, Opts) ->
    gen_server:start_link(?REF(NodeName, Module), ?MODULE, {NodeName, Module, Args}, Opts).


%%
%%  Return some info about the adapter.
%%
info(NodeName, Module, What) ->
    gen_server:call(?REF(NodeName, Module), {info, What}).


%%
%%  Set operation mode for domains, provided by the adapter.
%%
-spec domain_online(
        NodeName    :: atom(),
        Module      :: module(),
        DomainNames :: atom() | [atom()] | all,
        Direction   :: internal | external | all | both,
        Online      :: boolean()
    ) ->
        ok.

domain_online(NodeName, Module, DomainNames, Direction, Online) ->
    gen_server:call(?REF(NodeName, Module), {domain_online, DomainNames, Direction, Online}).


%%
%%  Checks, is particular domain is online.
%%  This function uses gproc to perform this, therefore is not using the adapter process.
%%
domain_online(NodeName, Module, DomainName, Direction) ->
    Domains = gproc:lookup_value(?REG(NodeName, Module)),
    #domain{internal = I, external = E} = lists:keyfind(DomainName, #domain.name, Domains),
    case Direction of
        internal -> I;
        external -> E
    end.



%%
%%  Executes command in the context of the particular domain.
%%  This function uses gproc to perform this, therefore is not using the adapter process.
%%
command(NodeName, Module, Domain, Direction, CommandName, CommandFun) ->
    {ok, CtxRef} = axb_context:push(),
    case domain_online(NodeName, Module, Domain, Direction) of
        true ->
            lager:debug("Executing ~p command ~p at ~p:~p:~p", [Direction, CommandName, NodeName, Module, Domain]),
            try timer:tc(CommandFun) of
                {DurationUS, Result} ->
                    ok = axb_stats:adapter_command_executed(NodeName, Module, Domain, Direction, CommandName, DurationUS),
                    lager:debug("Executing ~p command ~p done in ~pms", [Direction, CommandName, DurationUS / 1000]),
                    ok = axb_context:pop(CtxRef),
                    Result
            catch
                ErrType:ErrCode ->
                    ok = axb_stats:adapter_command_executed(NodeName, Module, Domain, Direction, CommandName, error),
                    lager:error(
                        "Executing ~p command ~p failed with ~p:~p, trace=~p",
                        [Direction, CommandName, ErrType, ErrCode, erlang:get_stacktrace()]
                    ),
                    ok = axb_context:pop(CtxRef),
                    {error, {ErrType, ErrCode}}
            end;
        false ->
            ok = axb_stats:adapter_command_executed(NodeName, Module, Domain, Direction, CommandName, error),
            lager:warning("Dropping ~p command ~p at ~p:~p:~p", [Direction, CommandName, NodeName, Module, Domain]),
            ok = axb_context:pop(CtxRef),
            {error, domain_offline}
    end.



%%% =============================================================================
%%% Callbacks for `gen_server`.
%%% =============================================================================

%%
%%
%%
init({NodeName, Module, Args}) ->
    case Module:provided_domains(Args) of
        {ok, DomainNames} ->
            Domains = [
                #domain{name = N, internal = false, external = false}
                || N <- DomainNames
            ],
            State = #state{
                node     = NodeName,
                module   = Module,
                args     = Args,
                domains = Domains
            },
            true = gproc:set_value(?REG(NodeName, Module), Domains),
            ok = axb_node:register_adapter(NodeName, Module, []),
            ok = axb_stats:adapter_registered(NodeName, Module, DomainNames),
            {ok, State}
    end.


%%
%%
%%
handle_call({domain_online, DomainNames, Direction, Online}, _From, State) ->
    #state{
        node = NodeName,
        module = Module,
        domains = Domains
    } = State,
    AvailableDomains = [ N || #domain{name = N} <- Domains ],
    AffectedDomains = case DomainNames of
        all                         -> AvailableDomains;
        _ when is_atom(DomainNames) -> [DomainNames];
        _ when is_list(DomainNames) -> lists:usort(DomainNames)
    end,
    [] = AffectedDomains -- AvailableDomains,
    ApplyActionFun = fun (Domain = #domain{name = DomainName}) ->
        case lists:member(DomainName, AffectedDomains) of
            true ->
                domain_mode_change(Domain, Direction, Online);
            false ->
                {Domain, []}
        end
    end,
    NewDomainsWithActions = lists:map(ApplyActionFun, Domains),
    NewDomains = [ S || {S, _} <- NewDomainsWithActions],
    ServActions = lists:append([ A || {_, A} <- NewDomainsWithActions]),
    true = gproc:set_value(?REG(NodeName, Module), NewDomains),    % NOTE: Possible race condition (vs domain_changed).
    NotifyActionsFun = fun ({Dom, D, O}) ->
        lager:info("Node ~p adapter ~p domain ~p direction=~p set online=~p", [NodeName, Module, Dom, D, O]),
        ok = Module:domain_changed(Dom, D, O)
    end,
    ok = lists:foreach(NotifyActionsFun, ServActions),
    NewState = State#state{domains = NewDomains},
    {reply, ok, NewState};

handle_call({info, What}, _From, State = #state{domains = Domains}) ->
    case What of
        domains ->
            DomainInfo = [ {N, I, E} || #domain{name = N, internal = I, external = E} <- Domains ],
            {reply, {ok, DomainInfo}, State};
        details ->
            Details = [
                {domains, [
                    {N, [
                        {internal, domain_status(I)},
                        {external, domain_status(E)}
                    ]}
                    || #domain{name = N, internal = I, external = E} <- Domains ]
                }
            ],
            {reply, {ok, Details}, State}
    end.


%%
%%
%%
handle_cast(_Message, State) ->
    {noreply, State}.


%%
%%
%%
handle_info(_Message, State) ->
    {noreply, State}.


%%
%%
%%
terminate(_Reason, _State) ->
    ok.

%%
%%
%%
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%%% =============================================================================
%%% Internal functions.
%%% =============================================================================

%%
%%  Returns domain state, after a change applied and actions, needed for that.
%%
domain_mode_change(Domain = #domain{name = Name, internal = Internal, external = External}, Direction, Online) ->
    {NewInternal, NewExternal} = case Direction of
        internal -> {Online,   External};
        external -> {Internal, Online};
        all      -> {Online,   Online};
        both     -> {Online,   Online}
    end,
    Actions = lists:append([
        case NewInternal =:= Internal of true -> []; false -> [{Name, internal, NewInternal}] end,
        case NewExternal =:= External of true -> []; false -> [{Name, external, NewExternal}] end
    ]),
    {Domain#domain{internal = NewInternal, external = NewExternal}, Actions}.


%%
%%
%%
domain_status(true) -> online;
domain_status(false) -> offline.

