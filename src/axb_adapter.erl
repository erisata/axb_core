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
%%% ESB Adapter behaviour.
%%%
%%% Main functions of this behaviour are the following:
%%%
%%%   * Allow management of domains, provided by the adapter (disable temporary, etc.);
%%%   * Collect metrics of the adapter operation;
%%%   * Define metadata, describing the adapter.
%%%
%%% TODO: Add support for user commands.
%%%
-module(axb_adapter).
-behaviour(gen_server).
-compile([{parse_transform, lager_transform}]).
-export([ref/2, start_link/5, start_link/6, info/3, domain_online/5, command/6]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-include("axb.hrl").

-define(REG(NodeName, AdapterName), {axb_adapter, NodeName, AdapterName}).
-define(REF(NodeName, AdapterName), {via, axb, ?REG(NodeName, AdapterName)}).

-type command_spec() :: axb_direction() | #{direction := axb_direction(), user_args => list()}.
-type domain_spec()  :: #{CommadName :: axb_command() := command_spec()}.

-type adapter_spec() ::
    #{
        description => binary() | iolist() | {priv, Filename :: string()} | {mfargs, module(), atom(), list()},
        domains => #{axb_domain() => domain_spec()}
    }.


%%% =============================================================================
%%% Callback definitions.
%%% =============================================================================

%%
%%  Initialize the adapter.
%%
-callback init(
        Arg :: term()
    ) ->
        {ok, AdapterSpec :: adapter_spec(), State :: term()} |
        {error, Reason :: term()}.


%%
%%  This callback notifies the adapter about changed domain states.
%%
-callback domain_change(
        DomainName  :: axb_domain(),
        Direction   :: axb_direction(),
        Online      :: boolean(),
        State       :: term()
    ) ->
        {ok, NewState :: term()}.


%%
%%  Code upgrades.
%%
-callback code_change(
        AdapterSpec :: adapter_spec(),
        State       :: term(),
        Extra       :: term()
    ) ->
        {ok, NewAdapterSpec :: adapter_spec(), NewState :: term()}.



%%% =============================================================================
%%% Internal state.
%%% =============================================================================

-record(domain, {
    name        :: term(),
    internal    :: boolean(),
    external    :: boolean()
}).

-record(state, {
    node        :: axb_node(),
    name        :: axb_adapter(),
    cb_mod      :: module(),
    cb_state    :: term(),
    spec        :: adapter_spec(),
    domains     :: [#domain{}]
}).



%%% =============================================================================
%%% Public API.
%%% =============================================================================

%%
%%  Creates a reference to the adapter, that can be used as {via, axb, Ref}.
%%
ref(NodeName, AdapterName) ->
    ?REF(NodeName, AdapterName).


%%
%%  Start the adapter with no user-defined registration.
%%
-spec start_link(
        NodeName    :: axb_node(),
        AdapterName :: axb_adapter(),
        CBModule    :: module(),
        Arg         :: term(),
        Opts        :: list()
    ) ->
        {ok, Pid :: pid()} | term().

start_link(NodeName, AdapterName, CBModule, Arg, Opts) ->
    gen_server:start_link(?MODULE, {NodeName, AdapterName, CBModule, Arg}, Opts).


%%
%%  Start the adapter with no user-defined registration.
%%
-spec start_link(
        RegName     :: term(),
        NodeName    :: axb_node(),
        AdapterName :: axb_adapter(),
        CBModule    :: module(),
        Arg         :: term(),
        Opts        :: list()
    ) ->
        {ok, Pid :: pid()} | term().

start_link(RegName, NodeName, AdapterName, CBModule, Arg, Opts) ->
    gen_server:start_link(RegName, ?MODULE, {NodeName, AdapterName, CBModule, Arg}, Opts).


%%
%%  Return some info about the adapter.
%%
info(NodeName, AdapterName, What) ->
    gen_server:call(?REF(NodeName, AdapterName), {info, What}).


%%
%%  Set operation mode for domains, provided by the adapter.
%%
-spec domain_online(
        NodeName    :: axb_node(),
        AdapterName :: axb_adapter(),
        DomainNames :: atom() | [atom()] | all,
        Direction   :: axb_direction() | all | both,
        Online      :: boolean()
    ) ->
        ok.

domain_online(NodeName, AdapterName, DomainNames, Direction, Online) ->
    gen_server:call(?REF(NodeName, AdapterName), {domain_online, DomainNames, Direction, Online}).


%%
%%  Checks, is particular domain is online.
%%  This function uses gproc to perform this, therefore is not using the adapter process.
%%
domain_online(NodeName, AdapterName, DomainName, Direction) ->
    Domains = axb:gproc_lookup_value(?REG(NodeName, AdapterName)),
    #domain{internal = I, external = E} = lists:keyfind(DomainName, #domain.name, Domains),
    case Direction of
        internal -> I;
        external -> E;
        map      -> #{internal => I, external => E};
        all      -> I and E;
        any      -> I or E
    end.



%%
%%  Executes command in the context of the particular domain.
%%  This function uses gproc to perform this, therefore is not using the adapter process.
%%
command(NodeName, AdapterName, DomainName, Direction, CommandName, CommandFun) ->
    {ok, CtxRef} = axb_context:push(),
    case domain_online(NodeName, AdapterName, DomainName, Direction) of
        true ->
            lager:debug("Executing ~p command ~p at ~p:~p:~p", [Direction, CommandName, NodeName, AdapterName, DomainName]),
            try timer:tc(CommandFun) of
                {DurationUS, Result} ->
                    ok = axb_stats:adapter_command_executed(NodeName, AdapterName, DomainName, Direction, CommandName, DurationUS),
                    lager:debug("Executing ~p command ~p done in ~pms", [Direction, CommandName, DurationUS / 1000]),
                    ok = axb_context:pop(CtxRef),
                    Result
            catch
                ErrType:ErrCode ->
                    ok = axb_stats:adapter_command_executed(NodeName, AdapterName, DomainName, Direction, CommandName, error),
                    lager:error(
                        "Executing ~p command ~p failed with ~p:~p, trace=~p",
                        [Direction, CommandName, ErrType, ErrCode, erlang:get_stacktrace()]
                    ),
                    ok = axb_context:pop(CtxRef),
                    {error, {ErrType, ErrCode}}
            end;
        false ->
            ok = axb_stats:adapter_command_executed(NodeName, AdapterName, DomainName, Direction, CommandName, error),
            lager:warning("Dropping ~p command ~p at ~p:~p:~p", [Direction, CommandName, NodeName, AdapterName, DomainName]),
            ok = axb_context:pop(CtxRef),
            {error, {offline, NodeName, AdapterName, CommandName}}
    end.



%%% =============================================================================
%%% Callbacks for `gen_server`.
%%% =============================================================================

%%
%%
%%
init({NodeName, AdapterName, CBModule, Arg}) ->
    case CBModule:init(Arg) of
        {ok, AdapterSpec = #{domains := DomainSpecs}, CBState} ->
            DomainNames = maps:keys(DomainSpecs),
            Domains = [
                #domain{name = N, internal = false, external = false}
                || N <- DomainNames
            ],
            State = #state{
                node     = NodeName,
                name     = AdapterName,
                cb_mod   = CBModule,
                cb_state = CBState,
                spec     = AdapterSpec,
                domains  = Domains
            },
            true = axb:gproc_reg(?REG(NodeName, AdapterName), Domains),
            ok = axb_node:register_adapter(NodeName, AdapterName, []),
            ok = axb_stats:adapter_registered(NodeName, AdapterName, DomainNames),
            {ok, State}
    end.


%%
%%
%%
handle_call({domain_online, DomainNames, Direction, Online}, _From, State) ->
    #state{
        node     = NodeName,
        name     = AdapterName,
        cb_mod   = CBModule,
        cb_state = CBState,
        domains  = Domains
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
    true = axb:gproc_set_value(?REG(NodeName, AdapterName), NewDomains),    % NOTE: Possible race condition (vs domain_changed).
    NotifyActionsFun = fun ({Dom, D, O}, CBS) ->
        lager:info("Node ~p adapter ~p domain ~p direction=~p set online=~p", [NodeName, AdapterName, Dom, D, O]),
        case CBModule:domain_change(Dom, D, O, CBS) of
            {ok, NCBS} ->
                NCBS
        end
    end,
    NewCBState = lists:foldl(NotifyActionsFun, CBState, ServActions),
    ok = axb_node_events:node_state_changed(NodeName, {adapter, AdapterName, domain_state}),
    NewState = State#state{
        cb_state = NewCBState,
        domains  = NewDomains
    },
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
%%  Code upgrades.
%%
code_change(_OldVsn, State = #state{spec = AdapterSpec, cb_mod = CBModule, cb_state = CBState}, Extra) ->
    case CBModule:code_change(AdapterSpec, CBState, Extra) of
        {ok, AdapterSpec, NewCBState} ->
            {ok, State#state{cb_state = NewCBState}}
        % TODO: Handle spec changes.
    end.



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


