-module(cache).
-export([lookup/2, add/4, remove/2]).

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
