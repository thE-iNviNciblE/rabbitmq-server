%%   The contents of this file are subject to the Mozilla Public License
%%   Version 1.1 (the "License"); you may not use this file except in
%%   compliance with the License. You may obtain a copy of the License at
%%   http://www.mozilla.org/MPL/
%%
%%   Software distributed under the License is distributed on an "AS IS"
%%   basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
%%   License for the specific language governing rights and limitations
%%   under the License.
%%
%%   The Original Code is the RabbitMQ Erlang Client.
%%
%%   The Initial Developers of the Original Code are LShift Ltd.,
%%   Cohesive Financial Technologies LLC., and Rabbit Technologies Ltd.
%%
%%   Portions created by LShift Ltd., Cohesive Financial
%%   Technologies LLC., and Rabbit Technologies Ltd. are Copyright (C)
%%   2007 LShift Ltd., Cohesive Financial Technologies LLC., and Rabbit
%%   Technologies Ltd.;
%%
%%   All Rights Reserved.
%%
%%   Contributor(s): ____________________.

%% @private
-module(amqp_connection_sup).

-include("amqp_client.hrl").

-behaviour(supervisor2).

-export([start_link/2]).
-export([init/1]).

%%---------------------------------------------------------------------------
%% Interface
%%---------------------------------------------------------------------------

start_link(Type, AmqpParams) ->
    Module = case Type of direct  -> amqp_direct_connection;
                          network -> amqp_network_connection
             end,
    {ok, Sup} = supervisor2:start_link([Module, AmqpParams]),
    [Connection] = supervisor2:find_child(Sup, connection),
    unlink(Sup),
    try Module:do_post_init(Connection) of
        ok -> link(Sup),
              {ok, Sup}
    catch
        exit:Reason -> {error, {auth_failure_likely, Reason}}
    end.

%%---------------------------------------------------------------------------
%% supervisor2 callbacks
%%---------------------------------------------------------------------------

init([Module, AmqpParams]) ->
    {ok, {{one_for_all, 0, 1},
          [connection, {Module, start_link, [AmqpParams]},
           permanent, ?MAX_WAIT, worker, [Module]],
          [channel_sup_sup, {amqp_channel_sup_sup, start_link, []},
           permanent, infinity, supervisor, [amqp_channel_sup_sup]]}}.
