-module(lock2).
-export([start/1]).

start(MyId) ->
    spawn(fun() -> init(MyId) end).

init(MyId) ->
	Clock = 0;
    receive
        {peers, Nodes} ->
            open(Nodes, MyId, Clock);
        stop ->
            ok
    end.

open(Nodes, MyId, Clock) ->
    receive
        {take, Master, Ref} ->
            Refs = requests(Nodes, MyId, Clock),
            wait(Nodes, Master, Refs, [], Ref, MyId);
        {request, From,  Ref, MyId, Clock} ->
			Clock = Clock + 1,
            From ! {ok, Ref},
            open(Nodes, MyId, Clock);
        stop ->
            ok
    end.

requests(Nodes, MyId, Clock) ->
    lists:map(
      fun(P) -> 
        R = make_ref(), 
        P ! {request, self(), R, MyId, Clock}, 
        R 
      end, 
      Nodes).

wait(Nodes, Master, [], Waiting, TakeRef, MyId, Clock) ->
    Master ! {taken, TakeRef},
    held(Nodes, Waiting, MyId, Clock);
wait(Nodes, Master, Refs, Waiting, TakeRef, MyId, Clock) ->
    receive
        {request, From, Ref, LockId, ClockReq} ->
			if Clock < ClockReq ->
				%Caso de el request es despues del nuestro
				Clock > ClockReq ->
				%Caso que el Request es anterior al nuestro
				Clock == ClockReq ->
				%Se mira por id, las siguientes sentencias
				if LockId < MyId -> 
					%Damos ok y hacemos request al mismo nodo para evitar posibles accesos concurrentes a la zona crítica.
					From ! {ok, Ref},
					New_ref = make_ref(),
					Clock = Clock + 1,
					From ! {request, self(), New_ref, MyId, Clock},
					wait(Nodes, Master, [New_ref|Refs], Waiting, TakeRef, MyId, Clock);
            true ->
                wait(Nodes, Master, Refs, [{From, Ref}|Waiting], TakeRef, MyId, Clock)
            end;
        {ok, Ref} ->
            NewRefs = lists:delete(Ref, Refs),
            wait(Nodes, Master, NewRefs, Waiting, TakeRef, MyId, Clock);
        release ->
            ok(Waiting),            
            open(Nodes, MyId, Clock)
    end.

ok(Waiting) ->
    lists:map(
      fun({F,R}) -> 
        F ! {ok, R} 
      end, 
      Waiting).

held(Nodes, Waiting, MyId, Clock) ->
    receive
        {request, From, Ref, MyId} ->
			Clock = Clock + 1,
            held(Nodes, [{From, Ref}|Waiting], MyId, Clock);
        release ->
            ok(Waiting),
            open(Nodes, MyId, Clock)
    end.
