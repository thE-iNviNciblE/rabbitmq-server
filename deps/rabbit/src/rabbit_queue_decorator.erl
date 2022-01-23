%% This Source Code Form is subject to the terms of the Mozilla Public
%% License, v. 2.0. If a copy of the MPL was not distributed with this
%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%
%% Copyright (c) 2007-2021 VMware, Inc. or its affiliates.  All rights reserved.
%%

-module(rabbit_queue_decorator).

-include_lib("rabbit_common/include/rabbit.hrl").
-include("amqqueue.hrl").

-export([select/1, set/1, register/2, unregister/1]).
-export([set/2, list/0]).

-behaviour(rabbit_registry_class).

-export([added_to_rabbit_registry/2, removed_from_rabbit_registry/1]).

%%----------------------------------------------------------------------------

-callback startup(amqqueue:amqqueue()) -> 'ok'.

-callback shutdown(amqqueue:amqqueue()) -> 'ok'.

-callback policy_changed(amqqueue:amqqueue(), amqqueue:amqqueue()) ->
    'ok'.

-callback active_for(amqqueue:amqqueue()) -> boolean().

%% called with Queue, MaxActivePriority, IsEmpty
-callback consumer_state_changed(
            amqqueue:amqqueue(), integer(), boolean()) -> 'ok'.

%%----------------------------------------------------------------------------

added_to_rabbit_registry(_Type, _ModuleName) -> ok.
removed_from_rabbit_registry(_Type) -> ok.

select(Modules) ->
    [M || M <- Modules, code:which(M) =/= non_existing].

set(Q) when ?is_amqqueue(Q) ->
    Decorators = [D || D <- list(), D:active_for(Q)],
    amqqueue:set_decorators(Q, Decorators).

set(Q, List) when ?is_amqqueue(Q) ->
    %% ETS queries are not allowed in khepri transactions, we need to lookup
    %% the registry before setting the decorators.
    Decorators = [D || D <- List, D:active_for(Q)],
    amqqueue:set_decorators(Q, Decorators).

list() -> [M || {_, M} <- rabbit_registry:lookup_all(queue_decorator)].

register(TypeName, ModuleName) ->
    rabbit_registry:register(queue_decorator, TypeName, ModuleName),
    [maybe_recover(Q) || Q <- rabbit_amqqueue:list()],
    ok.

unregister(TypeName) ->
    rabbit_registry:unregister(queue_decorator, TypeName),
    [maybe_recover(Q) || Q <- rabbit_amqqueue:list()],
    ok.

maybe_recover(Q0) when ?is_amqqueue(Q0) ->
    Name = amqqueue:get_name(Q0),
    Decs0 = amqqueue:get_decorators(Q0),
    Q1 = set(Q0),
    Decs1 = amqqueue:get_decorators(Q1),
    Old = lists:sort(select(Decs0)),
    New = lists:sort(select(Decs1)),
    case New of
        Old ->
            ok;
        _   ->
            %% TODO LRB JSP 160169569 should startup be passed Q1 here?
            [M:startup(Q0) || M <- New -- Old],
            rabbit_amqqueue:update_decorators(Name)
    end.
