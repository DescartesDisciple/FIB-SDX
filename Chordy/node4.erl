-module(node4).
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
    node(MyKey, Predecessor, Successor, nil, [], []).

connect(MyKey, nil) ->
    {ok, {MyKey, nil, self()}};

connect(_, PeerPid) ->
    Qref = make_ref(),
    PeerPid ! {key, Qref, self()},
    receive
        {Qref, Skey} ->
            Sref = monit(PeerPid),
            {ok, {Skey, Sref, PeerPid}}    %Punto de
    after ?Timeout ->
        io:format("Timeout: no response from ~w~n", [PeerPid])
    end.

schedule_stabilize() ->
    timer:send_interval(?Stabilize, self(), stabilize).

node(MyKey, Predecessor, Successor, Next, Store, Replica) ->
    receive
        {key, Qref, Peer} ->
            Peer ! {Qref, MyKey},
            node(MyKey, Predecessor, Successor, Next, Store, Replica);
        {notify, NewPeer} ->
            {NewPredecessor, NewStore} = notify(NewPeer, MyKey, Predecessor, Store),
            {_, _, Spid} = Successor,
            Spid ! {pushreplica, NewStore},
            node(MyKey, NewPredecessor, Successor, Next, NewStore, Replica);
        {request, Peer} ->
            request(Peer, Predecessor, Successor),
            node(MyKey, Predecessor, Successor, Next, Store, Replica);
        {status, Pred, Nx} ->
            {NewSuccessor, NewNext} = stabilize(Pred, Nx, MyKey, Successor),
            node(MyKey, Predecessor, NewSuccessor, NewNext, Store, Replica);
        {add, Key, Value, Qref, Client} ->
            Added = add(Key, Value, Qref, Client, MyKey, Predecessor, Successor, Store),
            node(MyKey, Predecessor, Successor, Next, Added, Replica);
        {lookup, Key, Qref, Client} ->
            lookup(Key, Qref, Client, MyKey, Predecessor, Successor, Store),
            node(MyKey, Predecessor, Successor, Next, Store, Replica);
        {handover, Elements} ->
            Merged = storage:merge(Store, Elements),
            {_, _, Spid} = Successor,
            Spid ! {pushreplica, Merged},
            node(MyKey, Predecessor, Successor, Next, Merged, Replica);
        {replicate, Key, Value} ->
            Merged = storage:merge(Replica, [{Key, Value}]),
            node(MyKey, Predecessor, Successor, Next, Store, Merged);
        {pushreplica, NewReplica} ->
            node(MyKey, Predecessor, Successor, Next, Store, NewReplica);
        stabilize ->
            stabilize(Successor),
            node(MyKey, Predecessor, Successor, Next, Store, Replica);
        stop ->
            ok;
        probe ->
            create_probe(MyKey, Successor, Store, Replica),
            node(MyKey, Predecessor, Successor, Next, Store, Replica);
        {probe, MyKey, Nodes, T} ->
            remove_probe(MyKey, Nodes, T),
            node(MyKey, Predecessor, Successor, Next, Store, Replica);
        {probe, RefKey, Nodes, T} ->
            forward_probe(RefKey, [MyKey|Nodes], T, Successor, Store, MyKey, Replica),
            node(MyKey, Predecessor, Successor, Next, Store, Replica);
        {'DOWN', Ref, process, _, _} ->
            {NewPred, NewSucc, NewNext, NewStore} = down(Ref, Predecessor, Successor, Next, Store, Replica),
            node(MyKey, NewPred, NewSucc, NewNext, NewStore, Replica)
   end.

down(Ref, {_, Ref, _}, Successor, Next, Store, Replica) ->
    Merged = storage:merge(Store, Replica),
    {nil, Successor, Next, Merged};
down(Ref, Predecessor, {_, Ref, _}, {Nkey, Npid}, Store, _) ->
    Nref = monit(Npid), %% Todo: ADD SOME CODE
    self() ! stabilize, %% Todo: ADD SOME CODE
    {Predecessor, {Nkey, Nref, Npid}, nil, Store}.

monit(Pid) ->
    erlang:monitor(process, Pid).

demonit(nil) ->
    ok;
demonit(MonitorRef) ->
    erlang:demonitor(MonitorRef, [flush]).


stabilize(Pred, Nx, MyKey, Successor) -> %% Igual hay que actualizar la función, la cabecera ya está ok
  {Skey, Sref, Spid} = Successor,
  case Pred of
      nil ->
          Spid ! {notify, {MyKey, self()}},
          {Successor, Nx};
      {MyKey, _, _} ->
          {Successor, Nx};
      {Skey, _, _} ->
          Spid ! {notify, {MyKey, self()}},
          {Successor, Nx};
      {Xkey, _, Xpid} -> %Caso en medio de dos
            case key:between(Xkey, MyKey, Skey) of
                true ->
                    self() ! stabilize, %stabilize(Pred, Mykey, Successor);
                    demonit(Sref),
                    Xref = monit(Xpid),
                    {{Xkey, Xref, Xpid}, {Skey, Spid}};
                false ->
                    Spid ! {notify, {MyKey, self()}},
                    {Successor, Nx}
            end
    end.

add(Key, Value, Qref, Client, MyKey, {Pkey, _, _}, {_, _, Spid}, Store) ->
    case key:between(Key, Pkey, MyKey) of %!
        true ->
            Added = storage:add(Key, Value, Store), %!
            Spid ! {replicate, Key, Value},
            Client ! {Qref, ok},
            Added;
        false ->
            Spid ! {add, Key, Value, Qref, Client}, %!
            Store
    end.

lookup(Key, Qref, Client, MyKey, {Pkey, _, _}, {_, _, Spid}, Store) ->
    case key:between(Key, Pkey, MyKey) of %!
        true ->
            Result = storage:lookup(Key, Store), %!
            Client ! {Qref, Result};
        false ->
            Spid ! {lookup, Key, Qref, Client}%!
    end.

stabilize({_, _, Spid}) ->
    Spid ! {request, self()}.

request(Peer, Predecessor, {Skey, _, Spid}) ->
    case Predecessor of
        nil ->
            Peer ! {status, nil, {Skey, Spid}};
        {Pkey, Pref ,Ppid} ->
            Peer ! {status, {Pkey, Pref, Ppid}, {Skey, Spid}}
    end.

handover(Store, MyKey, Nkey, Npid) ->
  {Keep, Leave} = storage:split(MyKey, Nkey, Store),
  Npid ! {handover, Leave},
  Keep.

notify({Nkey, Npid}, MyKey, Predecessor, Store) ->
    case Predecessor of
        nil ->
            Keep = handover(Store, MyKey, Nkey, Npid),
            Nref = monit(Npid),
            {{Nkey, Nref, Npid}, Keep}; %!
        {Pkey, Pref, _} ->
            case key:between(Nkey, Pkey, MyKey) of
                true ->
                    Keep = handover(Store, MyKey, Nkey, Npid), %!
                    demonit(Pref),
                    Nref = monit(Npid),
                    {{Nkey, Nref, Npid}, Keep}; %!
                false ->
                    {Predecessor, Store}
            end
    end.

create_probe(MyKey, {_, _, Spid}, Store, Replica) ->
    Spid ! {probe, MyKey, [MyKey], erlang:monotonic_time()},
    io:format("I am node: ~w, and I have ~w keys. My replica is: ~w~n",[MyKey, Store, Replica]),
    io:format("Create probe ~w!~n", [MyKey]).

remove_probe(MyKey, Nodes, T) ->
    T2 = erlang:monotonic_time(),
    Time = erlang:convert_time_unit(T2-T, native, millisecond),
    io:format("Received probe ~w in ~w ms Ring: ~w~n", [MyKey, Time, Nodes]).

forward_probe(RefKey, Nodes, T, {_, _, Spid}, Store, MyKey, Replica) ->
    Spid ! {probe, RefKey, Nodes, T},
    io:format("I am node: ~w, and I have ~w keys. My replica is: ~w~n",[MyKey, Store, Replica]),
    io:format("Forward probe ~w!~n", [RefKey]).
