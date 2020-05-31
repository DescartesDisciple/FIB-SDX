-module(causal).
-export([start/3]).

start(Id, Master, Jitter) ->
    spawn(fun() -> init(Id, Master, Jitter) end).

init(Id, Master, Jitter) ->
    receive
        {peers, Nodes} ->
            List = [],
            VC = newVC(length(Nodes), List),
            server(Id, Master, lists:delete(self(), Nodes), Jitter, VC, [])
    end.

newVC(0, List) ->
    list_to_tuple(List);
newVC(N, List) ->
    newVC(N-1, [0|List]).

%% Check if a message can be delivered to the master
checkMsg(_, _, _, 0) -> ready;
checkMsg(FromId, MsgVC, VC, FromId) ->
    if(element(FromId, MsgVC) == (element(FromId, VC) + 1)) -> %%Todo: COMPLETE, diapo 64 T4
        checkMsg(FromId, MsgVC, VC, FromId-1);
        true -> wait
    end;
checkMsg(FromId, MsgVC, VC, N) ->
    if (element(N, MsgVC) =< element(N, VC)) -> %%Todo: COMPLETE
        checkMsg(FromId, MsgVC, VC, N-1);
    true -> wait
end.

%% Deliver to the master all the ready messages in the hold-back queue
deliverReadyMsgs(_, VC, [], Queue) ->
    {VC, Queue};
deliverReadyMsgs(Master, VC, [{FromId, MsgVC, Msg}|Rest], Queue) ->
    case checkMsg(FromId, MsgVC, VC, size(VC)) of
        ready ->
            Master ! {deliver, Msg},
            Aux = element(FromId, VC),
            NewVC =  setelement(FromId, VC, Aux+1),
            %io:format("NewVC: ~w~n", [NewVC]),
            NewQueue = lists:delete({FromId, MsgVC, Msg}, Queue),
            deliverReadyMsgs(Master, NewVC, NewQueue, NewQueue);
        wait ->
            deliverReadyMsgs(Master, VC, Rest, Queue)
    end.


server(Id, Master, Nodes, Jitter, VC, Queue) ->
    receive
        {send, Msg} ->
            Aux = element(Id, VC),
            NewVC =  setelement(Id, VC, Aux+1),
            multicast(Msg, Nodes, Jitter, Id, NewVC),
            %io:format("NewVC: ~w~n", [NewVC]),
            Master ! {deliver, Msg},
            server(Id, Master, Nodes, Jitter, NewVC, Queue);
        {multicast, Msg, FromId, MsgVC} ->
            case checkMsg(FromId, MsgVC, VC, size(VC)) of
                ready ->
                    Master ! {deliver, Msg},
                    Aux = element(FromId, VC),
                    NewVC = setelement(FromId, VC, Aux+1),
                    %io:format("NewVC: ~w~n", [NewVC]),
                    {NewerVC, NewQueue} = deliverReadyMsgs(Master, NewVC, Queue, Queue),
                    server(Id, Master, Nodes, Jitter, NewerVC, NewQueue);
                wait ->
                    server(Id, Master, Nodes, Jitter, VC, [{FromId, MsgVC, Msg}|Queue])
            end;
        stop ->
            ok
    end.

multicast(Msg, Nodes, 0, FromId, MsgVC) ->
    lists:foreach(fun(Node) ->
                      Node ! {multicast, Msg, FromId, MsgVC}
                  end,
                  Nodes);
multicast(Msg, Nodes, Jitter, FromId, MsgVC) ->
    lists:foreach(fun(Node) ->
                      T = rand:uniform(Jitter),
                      timer:send_after(T, Node, {multicast, Msg, FromId, MsgVC})
                  end,
                  Nodes).
