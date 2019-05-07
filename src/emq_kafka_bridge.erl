%%--------------------------------------------------------------------
%% Copyright (c) 2015-2017 Feng Lee <feng@emqtt.io>.
%%
%% Modified by Ramez Hanna <rhanna@iotblue.net>
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

-module(emq_kafka_bridge).

-include("emq_kafka_bridge.hrl").
-include("id_generate_constants.hrl").

-include_lib("emqttd/include/emqttd.hrl").

%add
-import(string,[concat/2]).
-import(lists,[nth/2]). 

-export([load/1, unload/0]).

%% Hooks functions

-export([on_client_connected/3, on_client_disconnected/3]).

-export([on_client_subscribe/4, on_client_unsubscribe/4]).

% -export([on_session_created/3, on_session_subscribed/4, on_session_unsubscribed/4, on_session_terminated/4]).

% -export([on_message_publish/2]).

-export([on_message_publish/2, on_message_delivered/4, on_message_acked/4]).
% -export([on_message_publish/2, on_message_delivered/4]).

% -export([gen/0, new/0, timestamp/1]).

% -define(MAX_SEQ, 16#FFFF).



%% Called when the plugin application start
load(Env) ->
    ekaf_init([Env]),
    emqttd:hook('client.connected', fun ?MODULE:on_client_connected/3, [Env]),
    emqttd:hook('client.disconnected', fun ?MODULE:on_client_disconnected/3, [Env]),
    emqttd:hook('client.subscribe', fun ?MODULE:on_client_subscribe/4, [Env]),
    emqttd:hook('client.unsubscribe', fun ?MODULE:on_client_unsubscribe/4, [Env]),
    % emqttd:hook('session.created', fun ?MODULE:on_session_created/3, [Env]),
    % emqttd:hook('session.subscribed', fun ?MODULE:on_session_subscribed/4, [Env]),
    % emqttd:hook('session.unsubscribed', fun ?MODULE:on_session_unsubscribed/4, [Env]),
    % emqttd:hook('session.terminated', fun ?MODULE:on_session_terminated/4, [Env]),
    emqttd:hook('message.publish', fun ?MODULE:on_message_publish/2, [Env]),
    emqttd:hook('message.delivered', fun ?MODULE:on_message_delivered/4, [Env]),
    emqttd:hook('message.acked', fun ?MODULE:on_message_acked/4, [Env]).


on_client_connected(ConnAck, Client = #mqtt_client{client_id = ClientId, username = Username}, _Env) ->
    % io:format("client ~s/~s will connected: ~w.~n", [ClientId, Username, ConnAck]),
    Event = [{clientid, ClientId},
                {username, Username},
                {ts, timestamp()}],
    produce_kafka_connected(Event),
    {ok, Client}.

on_client_disconnected(Reason, _Client = #mqtt_client{client_id = ClientId, username = Username}, _Env) ->
    % io:format("client ~s/~s will connected: ~w~n", [ClientId, Username, Reason]),
    Event = [{clientid, ClientId},
                {username, Username},
                {ts, timestamp()}],
    produce_kafka_disconnected(Event),
    ok.


on_client_subscribe(ClientId, Username, TopicTable, _Env) ->
    % io:format("client(~s/~s) will subscribe: ~p~n", [Username, ClientId, TopicTable]),
    Event = [{clientid, ClientId},
                {username, Username},
                {topic, TopicTable},
                {ts, timestamp()}],
    produce_kafka_subscribe(Event),
    {ok, TopicTable}.
    
on_client_unsubscribe(ClientId, Username, TopicTable, _Env) ->
    % io:format("client(~s/~s) unsubscribe ~p~n", [ClientId, Username, TopicTable]),
    Event = [{clientid, ClientId},
                {username, Username},
                {topic, TopicTable},
                {ts, timestamp()}],
    produce_kafka_unsubscribe(Event),
    {ok, TopicTable}.

% on_session_created(ClientId, Username, _Env) ->
%     % io:format("session(~s/~s) created~n", [ClientId, Username]),
%     Event = [{action, connected},
%                 {clientid, ClientId},
%                 {username, Username}],
%     produce_kafka_log(Event).

% on_session_subscribed(ClientId, Username, {Topic, Opts}, _Env) ->
%     % io:format("session(~s/~s) subscribed: ~p~n", [Username, ClientId, {Topic, Opts}]),
%     {ok, {Topic, Opts}}.

% on_session_unsubscribed(ClientId, Username, {Topic, Opts}, _Env) ->
%     % io:format("session(~s/~s) unsubscribed: ~p~n", [Username, ClientId, {Topic, Opts}]),
%     ok.

% on_session_terminated(ClientId, Username, Reason, _Env) ->
%     % io:format("session(~s/~s/~s) terminated~n", [ClientId, Username, Reason]),
%     Event = [{action, disconnected},
%                 {clientid, ClientId},
%                 {username, Username}],
%     produce_kafka_log(Event).

%% transform message and return
on_message_publish(Message = #mqtt_message{topic = <<"$SYS/", _/binary>>}, _Env) ->
    % io:format("message publish: ~p.", [topic]),
    {ok, Message};

on_message_publish(Message, _Env) ->
    {ok, Payload} = format_payload(Message),
    produce_kafka_publish(Payload), 

    %add
    {_, Value} = lists:nth(4, Payload),


    Msg = Message#mqtt_message{payload = Value},
    {ok, Msg}.

on_message_delivered(ClientId, Username, Message, _Env) ->
    % io:format("delivered to client(~s/~s): ~s~n", [Username, ClientId, emqttd_message:format(Message)]),
    Event = [{clientid, ClientId},
                {username, Username},
                {topic, Message#mqtt_message.topic},
                {size, byte_size(Message#mqtt_message.payload)},
                {ts, emqttd_time:now_secs(Message#mqtt_message.timestamp)}],
    produce_kafka_delivered(Event),
    {ok, Message}.

on_message_acked(ClientId, Username, Message, _Env) ->
    % io:format("client(~s/~s) acked: ~s~n", [Username, ClientId, emqttd_message:format(Message)]),
    Event = [{action, <<"acked">>},
                {from_client_id, ClientId},
                {from_username, Username},
                {topic, Message#mqtt_message.topic},
                {qos, Message#mqtt_message.qos},
                {message, Message#mqtt_message.payload}],
    produce_kafka_publish(Event),
    {ok, Message}.

ekaf_init(_Env) ->
    {ok, BrokerValues} = application:get_env(emq_kafka_bridge, broker),
    KafkaHost = proplists:get_value(host, BrokerValues),
    KafkaPort = proplists:get_value(port, BrokerValues),
    KafkaPartitionStrategy= proplists:get_value(partitionstrategy, BrokerValues),
    KafkaPartitionWorkers= proplists:get_value(partitionworkers, BrokerValues),
    %KafkaPayloadTopic = proplists:get_value(payloadtopic, BrokerValues),
    %KafkaEventTopic = proplists:get_value(eventtopic, BrokerValues),
    KafkaPublishTopic = proplists:get_value(publishtopic, BrokerValues),
    KafkaConnectedTopic = proplists:get_value(connectedtopic, BrokerValues),
    KafkaDisconnectedTopic = proplists:get_value(disconnectedtopic, BrokerValues),
    KafkaSubscribeTopic = proplists:get_value(subscribetopic, BrokerValues),
    KafkaUnsubscribeTopic = proplists:get_value(unsubscribetopic, BrokerValues),
    KafkaDeliveredTopic = proplists:get_value(deliveredtopic, BrokerValues),

    %add
    % FluentdHost = proplists:get_value(fluentdhost, BrokerValues),
    % FluentdPort = proplists:get_value(fluentdport, BrokerValues),
    MessageHost = proplists:get_value(messagehost, BrokerValues),
    MessagePort = proplists:get_value(messageport, BrokerValues),


    application:set_env(ekaf, ekaf_bootstrap_broker,  {KafkaHost, list_to_integer(KafkaPort)}),
    % application:set_env(ekaf, ekaf_bootstrap_topics,  [<<"Processing">>, <<"DeviceLog">>]),
    application:set_env(ekaf, ekaf_partition_strategy, KafkaPartitionStrategy),
    application:set_env(ekaf, ekaf_per_partition_workers, KafkaPartitionWorkers),
    application:set_env(ekaf, ekaf_per_partition_workers_max, 10),
    % application:set_env(ekaf, ekaf_buffer_ttl, 10),
    % application:set_env(ekaf, ekaf_max_downtime_buffer_size, 5),
    ets:new(topic_table, [named_table, protected, set, {keypos, 1}]),
    % ets:insert(topic_table, {kafka_payload_topic, KafkaPayloadTopic}),
    % ets:insert(topic_table, {kafka_event_topic, KafkaEventTopic}),
    ets:insert(topic_table, {kafka_publish_topic, KafkaPublishTopic}),
    ets:insert(topic_table, {kafka_connected_topic, KafkaConnectedTopic}),
    ets:insert(topic_table, {kafka_disconnected_topic, KafkaDisconnectedTopic}),
    ets:insert(topic_table, {kafka_subscribe_topic, KafkaSubscribeTopic}),
    ets:insert(topic_table, {kafka_unsubscribe_topic, KafkaUnsubscribeTopic}),
    ets:insert(topic_table, {kafka_delivered_topic, KafkaDeliveredTopic}),
    %add
    % ets:insert(topic_table, {fluentd_host, FluentdHost}),
    % ets:insert(topic_table, {fluentd_port, FluentdPort}),
    ets:insert(topic_table, {message_host, MessageHost}),
    ets:insert(topic_table, {message_port, MessagePort}),
    % {ok, Socket} = gen_udp:open(0, [binary]),
    % ets:insert(topic_table, {fluentd_socket, Socket}),
    % {ok, _} = application:ensure_all_started(hackney),


    {ok, _} = application:ensure_all_started(gproc),
    {ok, _} = application:ensure_all_started(ekaf).

% format_event(Action, Client) ->
%     Event = [{action, Action},
%                 {clientid, Client#mqtt_client.client_id},
%                 {username, Client#mqtt_client.username}],
%     {ok, Event}.

format_payload(Message) ->
    {ClientId, Username} = format_from(Message#mqtt_message.from),

    %add
    % Method = get,
    % URL = <<"https://baidu.com">>,
    % Headers = [],
    % PayloadBody = <<>>,
    % Options = [],
    % {ok, StatusCode, RespHeaders, ClientRef} = hackney:request(Method, URL,Headers, PayloadBody, Options),
    % {ok, Body} = hackney:body(ClientRef),
    % ContentLength = byte_size(Body),

    Opts = [{framed, true}],
    [{_, MessageHost}] = ets:lookup(topic_table, message_host),
    [{_, MessagePort}] = ets:lookup(topic_table, message_port),
    {ok, Client} = thrift_client_util:new(MessageHost, list_to_integer(MessagePort), generate_thrift, Opts),
    % Req=#'example.Data'{text="hello"},
    {ClientAgain, {ok, {ResponseName, ResponseValue}}} = thrift_client:call(Client, do_generate, []),
    thrift_client:close(ClientAgain),
    JsonPayload2 = #{<<"payload">> => Message#mqtt_message.payload, <<"message_id">> => ResponseValue},
    % JsonPayload2 = #{<<"payload">> => Message#mqtt_message.payload, <<"message_id">> => Body},
    % JsonPayload2 = #{<<"payload">> => Message#mqtt_message.payload, <<"message_id">> => timestamp()},
    % JsonPayload2 = #{<<"payload">> => Message#mqtt_message.payload, <<"message_id">> => erlang:iolist_to_binary([protobuffs:encode(1, <<"Nick">>, string),protobuffs:encode(2, 25, uint32)])},
    JsonPayload3 = jsx:encode(JsonPayload2),
    Payload = [{clientid, ClientId},
                  {username, Username},
                  {topic, Message#mqtt_message.topic},
                  {payload, JsonPayload3},
                  {size, byte_size(Message#mqtt_message.payload)},
                  {ts, emqttd_time:now_secs(Message#mqtt_message.timestamp)}],
    % {ok, Socket} = gen_udp:open(0, [binary]),
    % [{_, Host}] = ets:lookup(topic_table, fluentd_host),
    % [{_, Port}] = ets:lookup(topic_table, fluentd_port),
    % [{_, Socket}] = ets:lookup(topic_table, fluentd_socket),
    % gen_udp:send(Socket, Host, list_to_integer(Port), <<"Hello,world">>),
    % gen_udp:close(Socket), 


    {ok, Payload}.

format_from({ClientId, Username}) ->
    {ClientId, Username};
format_from(From) when is_atom(From) ->
    {a2b(From), a2b(From)};
format_from(_) ->
    {<<>>, <<>>}.

a2b(A) -> erlang:atom_to_binary(A, utf8).

%% Called when the plugin application stop
unload() ->
    emqttd:unhook('client.connected', fun ?MODULE:on_client_connected/3),
    emqttd:unhook('client.disconnected', fun ?MODULE:on_client_disconnected/3),
    emqttd:unhook('client.subscribe', fun ?MODULE:on_client_subscribe/4),
    emqttd:unhook('client.unsubscribe', fun ?MODULE:on_client_unsubscribe/4),
    % emqttd:unhook('session.created', fun ?MODULE:on_session_created/3),
    % emqttd:unhook('session.subscribed', fun ?MODULE:on_session_subscribed/4),
    % emqttd:unhook('session.unsubscribed', fun ?MODULE:on_session_unsubscribed/4),
    % emqttd:unhook('session.terminated', fun ?MODULE:on_session_terminated/4),
    emqttd:unhook('message.publish', fun ?MODULE:on_message_publish/2),
    emqttd:unhook('message.delivered', fun ?MODULE:on_message_delivered/4),
    emqttd:unhook('message.acked', fun ?MODULE:on_message_acked/4).


% produce_kafka_payload(Message) ->
%     [{_, Topic}] = ets:lookup(topic_table, kafka_payload_topic),
%     % Topic = <<"Processing">>,
%     % io:format("send to kafka event topic: byte size: ~p~n", [byte_size(list_to_binary(Topic))]),    
%     % Payload = iolist_to_binary(mochijson2:encode(Message)),
%     Payload = jsx:encode(Message),
%     % ok = ekaf:produce_async(Topic, Payload),
%     ok = ekaf:produce_async(list_to_binary(Topic), Payload),
%     ok.

% produce_kafka_log(Message) ->
%     [{_, Topic}] = ets:lookup(topic_table, kafka_event_topic),
%     % Topic = <<"DeviceLog">>,
%     % io:format("send to kafka event topic: byte size: ~p~n", [byte_size(list_to_binary(Topic))]),    
%     % Payload = iolist_to_binary(mochijson2:encode(Message)),
%     Payload = jsx:encode(Message),
%     % ok = ekaf:produce_async(Topic, Payload),
%     ok = ekaf:produce_async(list_to_binary(Topic), Payload),
%     ok.

produce_kafka_publish(Message) ->
    [{_, Topic}] = ets:lookup(topic_table, kafka_publish_topic),
    % Topic = <<"Processing">>,
    % io:format("send to kafka event topic: byte size: ~p~n", [byte_size(list_to_binary(Topic))]),    
    % Payload = iolist_to_binary(mochijson2:encode(Message)),
    Payload = jsx:encode(Message),
    % ok = ekaf:produce_async(Topic, Payload),
    ok = ekaf:produce_async(list_to_binary(Topic), Payload),
    ok.

produce_kafka_connected(Message) ->
    [{_, Topic}] = ets:lookup(topic_table, kafka_connected_topic),
    % Topic = <<"Processing">>,
    % io:format("send to kafka event topic: byte size: ~p~n", [byte_size(list_to_binary(Topic))]),    
    % Payload = iolist_to_binary(mochijson2:encode(Message)),
    Payload = jsx:encode(Message),
    % ok = ekaf:produce_async(Topic, Payload),
    ok = ekaf:produce_async(list_to_binary(Topic), Payload),
    ok.

produce_kafka_disconnected(Message) ->
    [{_, Topic}] = ets:lookup(topic_table, kafka_disconnected_topic),
    % Topic = <<"Processing">>,
    % io:format("send to kafka event topic: byte size: ~p~n", [byte_size(list_to_binary(Topic))]),    
    % Payload = iolist_to_binary(mochijson2:encode(Message)),
    Payload = jsx:encode(Message),
    % ok = ekaf:produce_async(Topic, Payload),
    ok = ekaf:produce_async(list_to_binary(Topic), Payload),
    ok.

produce_kafka_unsubscribe(Message) ->
    [{_, Topic}] = ets:lookup(topic_table, kafka_unsubscribe_topic),
    % Topic = <<"Processing">>,
    % io:format("send to kafka event topic: byte size: ~p~n", [byte_size(list_to_binary(Topic))]),    
    % Payload = iolist_to_binary(mochijson2:encode(Message)),
    Payload = jsx:encode(Message),
    % ok = ekaf:produce_async(Topic, Payload),
    ok = ekaf:produce_async(list_to_binary(Topic), Payload),
    ok.

produce_kafka_subscribe(Message) ->
    [{_, Topic}] = ets:lookup(topic_table, kafka_subscribe_topic),
    % Topic = <<"Processing">>,
    % io:format("send to kafka event topic: byte size: ~p~n", [byte_size(list_to_binary(Topic))]),    
    % Payload = iolist_to_binary(mochijson2:encode(Message)),
    Payload = jsx:encode(Message),
    % ok = ekaf:produce_async(Topic, Payload),
    ok = ekaf:produce_async(list_to_binary(Topic), Payload),
    ok.

produce_kafka_delivered(Message) ->
    [{_, Topic}] = ets:lookup(topic_table, kafka_delivered_topic),
    % Topic = <<"Processing">>,
    % io:format("send to kafka event topic: byte size: ~p~n", [byte_size(list_to_binary(Topic))]),    
    % Payload = iolist_to_binary(mochijson2:encode(Message)),
    Payload = jsx:encode(Message),
    % ok = ekaf:produce_async(Topic, Payload),
    ok = ekaf:produce_async(list_to_binary(Topic), Payload),
    ok.

%add
timestamp() ->
    Ms = erlang:system_time(millisecond),
    Ran = random:uniform(99999999),
    list_to_binary(io_lib:format("~p", [Ms * 100000000 + Ran])).


