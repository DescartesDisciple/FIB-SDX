-module(cache).
-export([lookup/2, add/4, remove/2, purge/1]).

lookup(Req, Cache) ->
    case lists:keyfind(Req, 1, Cache) of
        false ->
            unknown;
        {Req, Expire, Entry} ->
            Now = erlang:monotonic_time(),
            ActTime = erlang:convert_time_unit(Now, native, second),
            if
                ActTime > Expire ->
                    invalid;
                true -> Entry
        end
    end.

add(Name, Expire, Reply, NewCache) -> lists:keystore(Name, 1, NewCache, {Name, Expire, Reply}).

remove(Name, Cache) -> lists:keydelete(Name, 1, Cache).

checktime(Elem) ->

    Now = erlang:monotonic_time(),
    ActTime = erlang:convert_time_unit(Now, native, second),
    if
        ActTime > element(2, Elem) ->
           false;
        true -> true
    end.

purge(Cache) -> lists:filter(fun checktime/1, Cache).
%Hay que recorrer toda la cache y ver si Expire < ActTime. Generar una cache nueva en la que ir metiendo los elementos
% de la cache antigua que sean válidos, se copian entradas correctas de una a otra.
