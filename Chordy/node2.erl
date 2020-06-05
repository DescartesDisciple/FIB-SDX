-module(node2).
-export([start/1, start/2]).

-define(Stabilize, 1000).
-define(Timeout, 5000).

start(MyKey) ->
    start(MyKey, nil).

start(MyKey, PeerPid) ->
    timer:start(),
    spawn(fun() -> init(MyKey, PeerPid) end).

init(MyKey, PeerPid) ->
    Predecessor = nil,
    {ok, Successor} = connect(MyKey, PeerPid),
    schedule_stabilize(),
    node(MyKey, Predecessor, Successor, []).

connect(MyKey, nil) ->
    {ok, {MyKey , self()}};
connect(_, PeerPid) ->
    Qref = make_ref(),
    PeerPid ! {key, Qref, self()},
    receive
        {Qref, Skey} ->
            {ok, {Skey, PeerPid}}    %Punto de
    after ?Timeout ->
        io:format("Timeout: no response from ~w~n", [PeerPid])
    end.

schedule_stabilize() ->
    timer:send_interval(?Stabilize, self(), stabilize).

node(MyKey, Predecessor, Successor, Store) ->
    receive
        {key, Qref, Peer} ->
            Peer ! {Qref, MyKey},
            node(MyKey, Predecessor, Successor, Store);
        {notify, NewPeer} ->
            {NewPredecessor, NewStore} = notify(NewPeer, MyKey, Predecessor, Store),
            node(MyKey, NewPredecessor, Successor, NewStore);
        {request, Peer} ->
            request(Peer, Predecessor),
            node(MyKey, Predecessor, Successor, Store);
        {status, Pred} ->
            NewSuccessor = stabilize(Pred, MyKey, Successor),
            node(MyKey, Predecessor, NewSuccessor, Store);
        {add, Key, Value, Qref, Client} ->
            Added = add(Key, Value, Qref, Client, MyKey, Predecessor, Successor, Store),
            node(MyKey, Predecessor, Successor, Added);
        {lookup, Key, Qref, Client} ->
            lookup(Key, Qref, Client, MyKey, Predecessor, Successor, Store),
            node(MyKey, Predecessor, Successor, Store);
        {handover, Elements} ->
            Merged = storage:merge(Store, Elements),
            node(MyKey, Predecessor, Successor, Merged);
        stabilize ->
            stabilize(Successor),
            node(MyKey, Predecessor, Successor, Store);
        stop ->
            ok;
        probe ->
            create_probe(MyKey, Successor, Store),
            node(MyKey, Predecessor, Successor, Store);
        {probe, MyKey, Nodes, T} ->
            remove_probe(MyKey, Nodes, T),
            node(MyKey, Predecessor, Successor, Store);
        {probe, RefKey, Nodes, T} ->
            forward_probe(RefKey, [MyKey|Nodes], T, Successor, Store, MyKey),
            node(MyKey, Predecessor, Successor, Store)
   end.

stabilize(Pred, MyKey, Successor) ->
  {Skey, Spid} = Successor,
  case Pred of
      nil ->
          Spid ! {notify, {MyKey, self()}},
          Successor;
      {MyKey, _} ->
          Successor;
      {Skey, _} -> %Nosotros somos el nuevo, hay que notificar
          Spid ! {notify, {MyKey, self()}},
          Successor;
      {Xkey, Xpid} -> %Caso en medio de dos
            case key:between(Xkey, MyKey, Skey) of
                true ->
                    self() ! stabilize, %stabilize(Pred, Mykey, Successor);
                    {Xkey, Xpid};
                false ->
                    Spid ! {notify, {MyKey, self()}},
                    Successor
            end
    end.

add(Key, Value, Qref, Client, MyKey, {Pkey, _}, {_, Spid}, Store) ->
    case key:between(Key, Pkey, MyKey) of %!
        true ->
            Added = storage:add(Key, Value, Store), %!
            Client ! {Qref, ok},
            Added;
        false ->
            Spid ! {add, Key, Value, Qref, Client}, %!
            Store
    end.

lookup(Key, Qref, Client, MyKey, {Pkey, _}, {_, Spid}, Store) ->
    case key:between(Key, Pkey, MyKey) of %!
        true ->
            Result = storage:lookup(Key, Store), %!
            Client ! {Qref, Result};
        false ->
            Spid ! {lookup, Key, Qref, Client}%!
    end.

stabilize({_, Spid}) ->
    Spid ! {request, self()}.

request(Peer, Predecessor) ->
    case Predecessor of
        nil ->
            Peer ! {status, nil};
        {Pkey, Ppid} ->
            Peer ! {status, {Pkey, Ppid}}
    end.

handover(Store, MyKey, Nkey, Npid) ->
  {Keep, Leave} = storage:split(MyKey, Nkey, Store),
  Npid ! {handover, Leave},
  Keep.

notify({Nkey, Npid}, MyKey, Predecessor, Store) ->
    case Predecessor of
        nil ->
            Keep = handover(Store, MyKey, Nkey, Npid),
            {{Nkey, Npid}, Keep}; %!
        {Pkey,  _} ->
            case key:between(Nkey, Pkey, MyKey) of
                true ->
                    Keep = handover(Store, MyKey, Nkey, Npid), %!
                    {{Nkey, Npid}, Keep}; %!
                false ->
                    {Predecessor, Store}
            end
    end.

create_probe(MyKey, {_, Spid}, Store) ->
    Spid ! {probe, MyKey, [MyKey], erlang:monotonic_time()},
    io:format("I am node: ~w, and I have ~w keys.~n",[MyKey, Store]),
    io:format("Create probe ~w!~n", [MyKey]).

remove_probe(MyKey, Nodes, T) ->
    T2 = erlang:monotonic_time(),
    Time = erlang:convert_time_unit(T2-T, native, millisecond),
    io:format("Received probe ~w in ~w ms Ring: ~w~n", [MyKey, Time, Nodes]).

forward_probe(RefKey, Nodes, T, {_, Spid}, Store, MyKey) ->
    Spid ! {probe, RefKey, Nodes, T},
    io:format("I am node: ~w, and I have ~w keys.~n",[MyKey, Store]),
    io:format("Forward probe ~w!~n", [RefKey]).
