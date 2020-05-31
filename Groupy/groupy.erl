  -module(groupy).
-export([start/2, stop/0]).

% We use the name of the module (i.e. gms3) as the parameter Module to the start procedure. Sleep stands for up to how many milliseconds the workers should wait until the next message is sent.

start(Module, Sleep) ->

    spawn('master@127.0.0.1', fun() -> register(a, worker:start("P1", Module, Sleep)) end),
    spawn('p1@127.0.0.1', fun() -> register(b, worker:start("P2", Module, {a, 'master@127.0.0.1'}, Sleep)) end),
    spawn('p2@127.0.0.1', fun() -> register(c, worker:start("P3", Module, {a, 'master@127.0.0.1'}, Sleep)) end),
    spawn('p3@127.0.0.1', fun() -> register(d, worker:start("P4", Module, {a, 'master@127.0.0.1'}, Sleep)) end),
    spawn('p4@127.0.0.1', fun() -> register(e, worker:start("P5", Module, {a, 'master@127.0.0.1'}, Sleep)) end).

stop() ->
    {a,'master@127.0.0.1'} ! stop,
    {b,'p1@127.0.0.1'} ! stop,
    {c,'p2@127.0.0.1'} ! stop,
    {d,'p3@127.0.0.1'} ! stop,
    {e,'p4@127.0.0.1'} ! stop.
