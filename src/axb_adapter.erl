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
%%%   * Allow management of services, provided by the adapter (disable temporary, etc.);
%%%   * Collect metrics of the adapter operation;
%%%   * Define metadata, describing the adapter.
%%%
%%% TODO: Rename Service to Domain.
%%%
-module(axb_adapter).
-behaviour(gen_server).
-compile([{parse_transform, lager_transform}]).
-export([start_link/4, info/3, service_online/5, command/6]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-define(REG(NodeName, Module), {n, l, {?MODULE, NodeName, Module}}).
-define(REF(NodeName, Module), {via, gproc, ?REG(NodeName, Module)}).


%%% =============================================================================
%%% Callback definitions.
%%% =============================================================================

%%
%%  This callback should return services, provided by this adapter.
%%
-callback provided_services(
        Args :: term()
    ) ->
        {ok, [ServiceName :: atom()]}.


%%
%%  This callback notifies the adapter about changed service states.
%%
-callback service_changed(
        ServiceName :: atom(),
        Direction   :: internal | external,
        Online      :: boolean()
    ) ->
        ok.


%%% =============================================================================
%%% Internal state.
%%% =============================================================================

-record(service, {
    name        :: term(),
    internal    :: boolean(),
    external    :: boolean()
}).

-record(state, {
    node        :: atom(),
    module      :: module(),
    args        :: term(),
    services    :: [#service{}]
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
%%  Set operation mode for services, provided by the adapter.
%%
-spec service_online(
        NodeName        :: atom(),
        Module          :: module(),
        ServiceNames    :: atom() | [atom()] | all,
        Direction       :: internal | external | all | both,
        Online          :: boolean()
    ) ->
        ok.

service_online(NodeName, Module, ServiceNames, Direction, Online) ->
    gen_server:call(?REF(NodeName, Module), {service_online, ServiceNames, Direction, Online}).


%%
%%  Checks, is particular service is online.
%%  This function uses gproc to perform this, therefore is not using the adapter process.
%%
service_online(NodeName, Module, ServiceName, Direction) ->
    Services = gproc:lookup_value(?REG(NodeName, Module)),
    #service{internal = I, external = E} = lists:keyfind(ServiceName, #service.name, Services),
    case Direction of
        internal -> I;
        external -> E
    end.



%%
%%  Executes command in the context of particular service.
%%  This function uses gproc to perform this, therefore is not using the adapter process.
%%
command(NodeName, Module, Service, Direction, CommandName, CommandFun) ->
    case service_online(NodeName, Module, Service, Direction) of
        true ->
            lager:debug("Executing ~p command ~p at ~p:~p:~p", [Direction, CommandName, NodeName, Module, Service]),
            % TODO: Add metrics here.
            % TODO: Generate CTX_ID here, if the calling process does not have one.
            CommandFun();
        false ->
            lager:warning("Dropping ~p command ~p at ~p:~p:~p", [Direction, CommandName, NodeName, Module, Service]),
            {error, service_offline}
    end.



%%% =============================================================================
%%% Callbacks for `gen_server`.
%%% =============================================================================

%%
%%
%%
init({NodeName, Module, Args}) ->
    case Module:provided_services(Args) of
        {ok, ServiceNames} ->
            Services = [
                #service{name = N, internal = false, external = false}
                || N <- ServiceNames
            ],
            State = #state{
                node     = NodeName,
                module   = Module,
                args     = Args,
                services = Services
            },
            true = gproc:set_value(?REG(NodeName, Module), Services),
            ok = axb_node:register_adapter(NodeName, Module, []),
            {ok, State}
    end.


%%
%%
%%
handle_call({service_online, ServiceNames, Direction, Online}, _From, State) ->
    #state{
        node = NodeName,
        module = Module,
        services = Services
    } = State,
    AvailableServices = [ N || #service{name = N} <- Services ],
    AffectedServices = case ServiceNames of
        all                          -> AvailableServices;
        _ when is_atom(ServiceNames) -> [ServiceNames];
        _ when is_list(ServiceNames) -> lists:usort(ServiceNames)
    end,
    [] = AffectedServices -- AvailableServices,
    ApplyActionFun = fun (Service = #service{name = ServiceName}) ->
        case lists:member(ServiceName, AffectedServices) of
            true ->
                service_mode_change(Service, Direction, Online);
            false ->
                {Service, []}
        end
    end,
    NewServicesWithActions = lists:map(ApplyActionFun, Services),
    NewServices = [ S || {S, _} <- NewServicesWithActions],
    ServActions = lists:append([ A || {_, A} <- NewServicesWithActions]),
    true = gproc:set_value(?REG(NodeName, Module), NewServices),    % NOTE: Possible race condition (vs service_changed).
    NotifyActionsFun = fun ({SN, D, O}) ->
        lager:info("Node ~p adapter ~p service ~p direction=~p set online=~p", [NodeName, Module, SN, D, O]),
        ok = Module:service_changed(SN, D, O)
    end,
    ok = lists:foreach(NotifyActionsFun, ServActions),
    NewState = State#state{services = NewServices},
    {reply, ok, NewState};

handle_call({info, What}, _From, State = #state{services = Services}) ->
    case What of
        services ->
            ServiceInfo = [ {N, I, E} || #service{name = N, internal = I, external = E} <- Services ],
            {reply, {ok, ServiceInfo}, State}
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
%%  Returns service state, after a change applied and actions, needed for that.
%%
service_mode_change(Service = #service{name = Name, internal = Internal, external = External}, Direction, Online) ->
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
    {Service#service{internal = NewInternal, external = NewExternal}, Actions}.


