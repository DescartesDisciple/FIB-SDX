-module(muty).
-export([start/3, stop/0]).

% We use the name of the module (i.e. lock3) as a parameter to the start procedure. We also provide the average time (in milliseconds) the worker is going to sleep before trying to get the lock (Sleep) and work with the lock taken (Work).

start(Lock, Sleep, Work) ->

    spawn('p1@127.0.0.1', fun() -> register(l1, apply(Lock, start, [1])) 
                          end),
    spawn('p2@127.0.0.1', fun() -> register(l2, apply(Lock, start, [2])) 
                          end),
    spawn('p3@127.0.0.1', fun() -> register(l3, apply(Lock, start, [3])) 
                          end),
    spawn('p4@127.0.0.1', fun() -> register(l4, apply(Lock, start, [4])) 
                          end),
    {l1,'p1@127.0.0.1'} ! {peers, [{l2,'p2@127.0.0.1'}, {l3,'p3@127.0.0.1'}, {l4,'p4@127.0.0.1'}]},
    {l2,'p2@127.0.0.1'} ! {peers, [{l1,'p1@127.0.0.1'}, {l3,'p3@127.0.0.1'}, {l4,'p4@127.0.0.1'}]},
    {l3,'p3@127.0.0.1'} ! {peers, [{l1,'p1@127.0.0.1'}, {l2,'p2@127.0.0.1'}, {l4,'p4@127.0.0.1'}]},
    {l4,'p4@127.0.0.1'} ! {peers, [{l1,'p1@127.0.0.1'}, {l2,'p2@127.0.0.1'}, {l3,'p3@127.0.0.1'}]},
    spawn('p1@127.0.0.1', fun() -> register(w1, worker:start("John", l1, Sleep, Work)) 
                          end),
    spawn('p2@127.0.0.1', fun() -> register(w2, worker:start("Ringo", l2, Sleep, Work)) 
                          end),
    spawn('p3@127.0.0.1', fun() -> register(w3, worker:start("Paul", l3, Sleep, Work)) 
                          end),
    spawn('p4@127.0.0.1', fun() -> register(w4, worker:start("George", l4, Sleep, Work)) 
                          end),
	ok.

stop() ->
    {w1,'p1@127.0.0.1'} ! stop,
    {w2,'p2@127.0.0.1'} ! stop,
    {w3,'p3@127.0.0.1'} ! stop,
    {w4,'p4@127.0.0.1'} ! stop.
