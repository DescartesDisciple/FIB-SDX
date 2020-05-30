-module(lock2).
-export([start/1]).

start(MyId) ->
    spawn(fun() -> init(MyId) end).

init(MyId) ->
    receive
        {peers, Nodes} ->
            open(Nodes, MyId);
        stop ->
            ok
    end.

open(Nodes, MyId) ->
    receive
        {take, Master, Ref} ->
            Refs = requests(Nodes, MyId),
            wait(Nodes, Master, Refs, [], Ref, MyId);
        {request, From,  Ref, MyId} ->
            From ! {ok, Ref},
            open(Nodes, MyId);
        stop ->
            ok
    end.

requests(Nodes, MyId) ->
    lists:map(
      fun(P) -> 
        R = make_ref(), 
        P ! {request, self(), R, MyId}, 
        R 
      end, 
      Nodes).

wait(Nodes, Master, [], Waiting, TakeRef, MyId) ->
    Master ! {taken, TakeRef},
    held(Nodes, Waiting, MyId);
wait(Nodes, Master, Refs, Waiting, TakeRef, MyId) ->
    receive
        {request, From, Ref, LockId} ->
            if LockId < MyId -> 
                %Damos ok y hacemos request al mismo nodo para evitar posibles accesos concurrentes a la zona crítica.
                From ! {ok, Ref},
                New_ref = make_ref(),
                From ! {request, self(), New_ref, MyId},
                wait(Nodes, Master, [New_ref|Refs], Waiting, TakeRef, MyId);
            true ->
                wait(Nodes, Master, Refs, [{From, Ref}|Waiting], TakeRef, MyId)
            end;
        {ok, Ref} ->
            NewRefs = lists:delete(Ref, Refs),
            wait(Nodes, Master, NewRefs, Waiting, TakeRef, MyId);
        release ->
            ok(Waiting),            
            open(Nodes, MyId)
    end.

ok(Waiting) ->
    lists:map(
      fun({F,R}) -> 
        F ! {ok, R} 
      end, 
      Waiting).

held(Nodes, Waiting, MyId) ->
    receive
        {request, From, Ref, MyId} ->
            held(Nodes, [{From, Ref}|Waiting], MyId);
        release ->
            ok(Waiting),
            open(Nodes, MyId)
    end.
