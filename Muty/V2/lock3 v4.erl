-module(lock3).
-export([start/1]).

start(MyId) ->
    spawn(fun() -> init(MyId) end).

init(MyId) ->
    receive
        {peers, Nodes} ->
            open(Nodes, MyId, 0);
        stop ->
            ok
    end.

open(Nodes, MyId, Clock) ->
    receive
        {take, Master, Ref} ->
        	% Incrementamos reloj local cuando intentamos acceder a región crítica
        	%IncClock = Clock + 1,
            Refs = requests(Nodes, MyId, Clock + 1),
            wait(Nodes, Master, Refs, [], Ref, MyId, Clock + 1);
        {request, From,  Ref, MyId, ClockReq} ->
			% Actualizamos reloj local cuando recibimos request
			From ! {ok, Ref},
            open(Nodes, MyId, max(Clock, ClockReq));
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
wait(Nodes, Master, Refs, Waiting, TakeRef, MyId, Clock) -> %al wait hay que pasarle dos clocks para poder comparar con todos los nodos??
    receive
        {request, From, Ref, LockId, ClockReq} -> %%%%%%%%%%%%FALTA HAER SYNC DE LOS DOS CLOCKS
			%Si local anterior a remoto, no se da ok, se pone nodo en cola de wait
			if Clock < ClockReq ->  wait(Nodes, Master, Refs, [{From, Ref}|Waiting], TakeRef, MyId, Clock);
				%Si local y remoto iguales desempatar con id (prioridades)
				Clock == ClockReq ->
					if LockId < MyId -> From ! {ok, Ref}; %Damos ok
            		true -> %no se da ok y se pone nodo en cola de wait
             			wait(Nodes, Master, Refs, [{From, Ref}|Waiting], TakeRef, MyId, Clock)
             		end;
             	true -> %Si remoto anterior a local, se da ok
             		From ! {ok, Ref}
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
        {request, From, Ref, MyId, ClockReq} -> % en el request falta el clock de quien hace request
			held(Nodes, [{From, Ref}|Waiting], MyId, max(Clock, ClockReq); % pillar maximo de los dos clocks
        release ->
            ok(Waiting),
            open(Nodes, MyId, Clock)
    end.
