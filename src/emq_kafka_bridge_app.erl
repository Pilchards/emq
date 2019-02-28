%%--------------------------------------------------------------------
%% Copyright (c) 2015-2017 Feng Lee <feng@emqtt.io>.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

-module(emq_kafka_bridge_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    {ok, Sup} = emq_kafka_bridge_sup:start_link(),
    % ok = emq_access_control:register_mod(auth, emq_auth_emq_kafka_bridge, []),
    % ok = emq_access_control:register_mod(acl, emq_acl_emq_kafka_bridge, []),
    emq_kafka_bridge:load(application:get_all_env()),
    {ok, Sup}.

stop(_State) ->
    % ok = emq_access_control:unregister_mod(auth, emq_auth_emq_kafka_bridge),
    % ok = emq_access_control:unregister_mod(acl, emq_acl_emq_kafka_bridge),
    emq_kafka_bridge:unload().

