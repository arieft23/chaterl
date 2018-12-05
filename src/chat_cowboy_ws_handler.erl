-module(chat_cowboy_ws_handler).
-import(string,[concat/2]).
-export([init/3]).
-export([websocket_init/3]).
-export([websocket_handle/3]).
-export([websocket_info/3]).
-export([websocket_terminate/3]).

-define(CHATROOM_NAME, ?MODULE).
-define(TIMEOUT, 5 * 60 * 1000). % Innactivity Timeout

-record(state, {name, username, handler}).

%% API

init(_, _Req, _Opts) ->
  {upgrade, protocol, cowboy_websocket}.

websocket_init(_Type, Req, _Opts) ->
  % Create the handler from our custom callback
  Handler = ebus_proc:spawn_handler(fun chat_erlbus_handler:handle_msg/2, [self()]),
  ebus:sub(Handler, ?CHATROOM_NAME),
  {ok, Req, #state{name = get_name(Req), username= <<"default">> , handler = Handler}}.

websocket_handle({text, Msg}, Req, State) ->
  {ok, {Type, Msg1}} = parse_message(Msg),
  case Type of
      <<"initname">> ->
          NewState = #state{name = State#state.name, username=Msg1 , handler = State#state.handler},
          ebus:pub(?CHATROOM_NAME, {<<"System:">>, <<"Bergabung chat">>, Msg1}),
          {ok, Req, NewState};
      <<"setname">> ->
        NewState = #state{name = State#state.name, username=Msg1 , handler = State#state.handler},
        ebus:pub(?CHATROOM_NAME, {State#state.username, Msg1, <<"Melakukan Ganti Nama Menjadi">>}),
        {ok, Req, NewState};
      <<"chat">> ->
        ebus:pub(?CHATROOM_NAME, {Msg1, State#state.username}),
        {ok, Req, State}
  end;
  
websocket_handle(_Data, Req, State) ->
  {ok, Req, State}.

websocket_info({message_published, {Sender, Msg, Username}}, Req, State) ->
  {reply, {text, jiffy:encode({[{sender, Sender}, {username, Username}, {msg, Msg}]})}, Req, State};
websocket_info({message_published, {Msg, Username}}, Req, State) ->
    {reply, {text, jiffy:encode({[{sender, ""}, {username, Username}, {msg, Msg}]})}, Req, State};    
websocket_info(_Info, Req, State) ->
  {ok, Req, State}.

websocket_terminate(_Reason, _Req, State) ->
  % Unsubscribe the handler
  ebus:unsub(State#state.handler, ?CHATROOM_NAME),
  ok.

%% Private methods

get_name(Req) ->
  {{Host, Port}, _} = cowboy_req:peer(Req),
  Name = list_to_binary(string:join([inet_parse:ntoa(Host), 
    ":", io_lib:format("~p", [Port])], "")),
  Name.

parse_message(Msg) ->
    {struct, Msg1}         = mochijson2:decode(Msg),
    {<<"type">>, Type}     = lists:keyfind(<<"type">>, 1, Msg1),
    {<<"msg">>,  Content}  = lists:keyfind(<<"msg">>, 1, Msg1),
    {ok, {Type, Content}}.