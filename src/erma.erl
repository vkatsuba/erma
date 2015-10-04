-module(erma).

-export([build/1, append/2]).
-import(erma_utils, [prepare_table_name/1, prepare_name/1, prepare_value/1]).
-include("erma.hrl").


%%% module API

-spec build(sql_query()) -> sql().
build({select, Fields, Table}) -> build_select("SELECT ", Fields, Table, []);
build({select, Fields, Table, Entities}) -> build_select("SELECT ", Fields, Table, Entities);
build({select_distinct, Fields, Table}) -> build_select("SELECT DISTINCT ", Fields, Table, []);
build({select_distinct, Fields, Table, Entities}) -> build_select("SELECT DISTINCT ", Fields, Table, Entities);
build({insert, Table, Names, Values}) -> build_insert(Table, Names, [Values], []);
build({insert, Table, Names, Values, Entities}) -> build_insert(Table, Names, [Values], Entities);
build({insert_rows, Table, Names, Rows}) -> build_insert(Table, Names, Rows, []);
build({insert_rows, Table, Names, Rows, Entities}) -> build_insert(Table, Names, Rows, Entities);
build({update, Table, KV}) -> build_update(Table, KV, []);
build({update, Table, KV, Entities}) -> build_update(Table, KV, Entities);
build({delete, Table}) -> build_delete(Table, []);
build({delete, Table, Entities}) -> build_delete(Table, Entities).


-spec build_select(string(), [field()], table_name(), [joins() | where() | order() | limit()]) -> sql().
build_select(Select, Fields, Table, Entities) ->
    unicode:characters_to_binary([Select, build_fields(Fields), " FROM ",
                                  prepare_table_name(Table),
                                  build_joins(Table, Entities),
                                  build_where(Entities),
                                  build_group(Entities),
                                  build_having(Entities),
                                  build_order(Entities),
                                  build_limit(Entities)
                                 ]).


-spec build_insert(table_name(), [name()], [[value()]], [returning()]) -> sql().
build_insert(Table, Names, Rows, Entities) ->
    Names2 = case Names of
                [] -> [];
                _ -> N1 = lists:map(fun erma_utils:prepare_name/1, Names),
                     N2 = string:join(N1, ", "),
                     [" (", N2, ")"]
            end,
    Rows2 = lists:map(fun(V1) ->
                                V2 = lists:map(fun erma_utils:prepare_value/1, V1),
                                ["(", string:join(V2, ", "), ")"]
                        end, Rows),
    Rows3 = string:join(Rows2, ", "),
    unicode:characters_to_binary(["INSERT INTO ",
                                  prepare_table_name(Table),
                                  Names2, " VALUES ", Rows3,
                                  build_returning(Entities)]).


-spec build_update(table_name(), [{name(), value()}], [where() | returning()]) -> sql().
build_update(Table, KV, Entities) ->
    Values = lists:map(fun({K, V}) ->
                               [prepare_name(K), " = ", prepare_value(V)]
                       end, KV),
    Values2 = string:join(Values, ", "),
    unicode:characters_to_binary(["UPDATE ", prepare_table_name(Table),
                                  " SET ", Values2,
                                  build_where(Entities),
                                  build_returning(Entities)]).


-spec build_delete(table_name(), [where() | returning()]) -> sql().
build_delete(Table, Entities) ->
    unicode:characters_to_binary(["DELETE FROM ", prepare_table_name(Table),
                                  build_where(Entities),
                                  build_returning(Entities)]).


-spec append(sql_query(), list()) -> sql_query().
append({select, Fields, Table}, NewEntities) -> {select, Fields, Table, NewEntities};
append({select, Fields, Table, Entities}, NewEntities) -> {select, Fields, Table, merge(Entities, NewEntities)};
append({select_distinct, Fields, Table}, NewEntities) -> {select_distinct, Fields, Table, NewEntities};
append({select_distinct, Fields, Table, Entities}, NewEntities) -> {select_distinct, Fields, Table, merge(Entities, NewEntities)};
append({update, Table, KV}, NewEntities) -> {update, Table, KV, NewEntities};
append({update, Table, KV, Entities}, NewEntities) -> {update, Table, KV, merge(Entities, NewEntities)};
append({delete, Table}, NewEntities) -> {delete, Table, NewEntities};
append({delete, Table, Entities}, NewEntities) -> {delete, Table, merge(Entities, NewEntities)};
append(Query, _NewEntities) -> Query.


%%% inner functions

-spec build_fields([field()]) -> iolist().
build_fields([]) -> "*";
build_fields(Fields) ->
    Fields2 = lists:map(fun({AggFun, Name, as, Alias}) ->
                                [string:to_upper(atom_to_list(AggFun)),
                                 "(", prepare_name(Name), ") AS ", prepare_name(Alias)];
                           ({Name, as, Alias}) ->
                                [prepare_name(Name), " AS ", prepare_name(Alias)];
                           ({raw, Name}) -> Name;
                           ({AggFun, Name}) ->
                                [string:to_upper(atom_to_list(AggFun)),
                                 "(", prepare_name(Name), ")"];
                           (Name) ->
                                prepare_name(Name)
                        end, Fields),
    string:join(Fields2, ", ").


-spec build_joins(table_name(), list()) -> iolist().
build_joins(MainTable, Entities) ->
    case lists:keyfind(joins, 1, Entities) of
        false -> [];
        {joins, []} -> [];
        {joins, JEntities} ->
            Joins = lists:map(
                      fun({JoinType, {JoinTable, ToTable}}) -> build_join_entity(JoinType, JoinTable, ToTable, []);
                         ({JoinType, {JoinTable, ToTable}, Props}) -> build_join_entity(JoinType, JoinTable, ToTable, Props);
                         ({JoinType, JoinTable}) -> build_join_entity(JoinType, JoinTable, MainTable, []);
                         ({JoinType, JoinTable, Props}) -> build_join_entity(JoinType, JoinTable, MainTable, Props)
                      end, JEntities),
            case lists:flatten(Joins) of
                [] -> [];
                _ -> [" ", string:join(Joins, " ")]
            end
    end.


-spec build_join_entity(join_type(), table_name(), table_name(), [join_prop()]) -> iolist().
build_join_entity(JoinType, JoinTable, ToTable, JoinProps) ->
    Join = case JoinType of
               inner -> "INNER JOIN ";
               left -> "LEFT JOIN ";
               right -> "RIGHT JOIN ";
               full -> "FULL JOIN "
           end,
    Table = prepare_table_name(JoinTable),
    ToAlias = case ToTable of
                  {_, as, Alias2} -> prepare_name(Alias2);
                  Name2 -> prepare_name(Name2)
              end,
    {JoinName, JoinAlias} =
        case JoinTable of
            {Name3, as, Alias3} -> {Name3, prepare_name(Alias3)};
            Name4 -> {Name4, prepare_name(Name4)}
        end,
    PrimaryKey = case lists:keyfind(pk, 1, JoinProps) of
                     false -> "id";
                     {pk, Pk} -> prepare_name(Pk)
                 end,
    ForeignKey = case lists:keyfind(fk, 1, JoinProps) of
                     false -> prepare_name([JoinName, "_id"]);
                     {fk, Fk} -> prepare_name(Fk)
                 end,
    io:format("ToAlias:~p, JoinName:~p, ForeignKey:~p~n", [ToAlias, JoinName, ForeignKey]),
    [Join, Table, " ON ", JoinAlias, ".", PrimaryKey, " = ", ToAlias, ".", ForeignKey].


-spec build_where(list()) -> iolist().
build_where(Conditions) ->
    case lists:keyfind(where, 1, Conditions) of
        false -> [];
        {where, []} -> [];
        {where, WConditions} ->
            W1 = lists:map(fun build_where_condition/1, WConditions),
            case lists:flatten(W1) of
                [] -> [];
                _ -> W2 = string:join(W1, " AND "),
                     [" WHERE ", W2]
            end
    end.

-spec build_where_condition(where_condition()) -> iolist().
build_where_condition({'not', WEntity}) ->
    ["(NOT ", build_where_condition(WEntity), ")"];
build_where_condition({'or', []}) -> [];
build_where_condition({'or', WConditions}) ->
    W = lists:map(fun build_where_condition/1, WConditions),
    case W of
        [] -> [];
        _ -> ["(", string:join(W, " OR "), ")"]
    end;
build_where_condition({'and', []}) -> [];
build_where_condition({'and', WConditions}) ->
    W = lists:map(fun build_where_condition/1, WConditions),
    case lists:flatten(W) of
        [] -> [];
        _ -> ["(", string:join(W, " AND "), ")"]
    end;
build_where_condition({Key, '=', Value}) ->
    [prepare_name(Key), " = ", build_where_value(Value)];
build_where_condition({Key, '<>', Value}) ->
    [prepare_name(Key), " <> ", build_where_value(Value)];
build_where_condition({Key, '>', Value}) ->
    [prepare_name(Key), " > ", build_where_value(Value)];
build_where_condition({Key, gt, Value}) ->
    [prepare_name(Key), " > ", build_where_value(Value)];
build_where_condition({Key, '<', Value}) ->
    [prepare_name(Key), " < ", build_where_value(Value)];
build_where_condition({Key, lt, Value}) ->
    [prepare_name(Key), " < ", build_where_value(Value)];
build_where_condition({Key, '>=', Value}) ->
    [prepare_name(Key), " >= ", build_where_value(Value)];
build_where_condition({Key, '<=', Value}) ->
    [prepare_name(Key), " <= ", build_where_value(Value)];
build_where_condition({Key, true}) ->
    [prepare_name(Key), " = true"];
build_where_condition({Key, false}) ->
    [prepare_name(Key), " = false"];
build_where_condition({Key, like, Value}) when is_list(Value) ->
    [prepare_name(Key), " LIKE ", build_where_value(Value)];
build_where_condition({Key, in, []}) ->
    [prepare_name(Key), " IN (NULL)"];
build_where_condition({Key, in, Values}) when is_list(Values) ->
    V = lists:map(fun build_where_value/1, Values),
    [prepare_name(Key), " IN (", string:join(V, ", "), ")"];
build_where_condition({Key, in, SubQuery}) when is_tuple(SubQuery) ->
    [prepare_name(Key), " IN ", build_where_value(SubQuery)];
build_where_condition({Key, not_in, []}) ->
    [prepare_name(Key), " NOT IN (NULL)"];
build_where_condition({Key, not_in, Values}) when is_list(Values) ->
    V = lists:map(fun build_where_value/1, Values),
    [prepare_name(Key), " NOT IN (", string:join(V, ", "), ")"];
build_where_condition({Key, not_in, SubQuery}) when is_tuple(SubQuery) ->
    [prepare_name(Key), " NOT IN ", build_where_value(SubQuery)];
build_where_condition({Key, between, Value1, Value2}) ->
    [prepare_name(Key), " BETWEEN ", build_where_value(Value1), " AND ", build_where_value(Value2)];
build_where_condition({Key, Value}) ->
    [prepare_name(Key), " = ", build_where_value(Value)].


build_where_value({select, _, _} = Query) -> ["(", build(Query), ")"];
build_where_value({select, _, _, _} = Query) -> ["(", build(Query), ")"];
build_where_value({select_distinct, _, _} = Query) -> ["(", build(Query), ")"];
build_where_value({select_distinct, _, _, _} = Query) -> ["(", build(Query), ")"];
build_where_value(Value) -> prepare_value(Value).


-spec build_group(list()) -> iolist().
build_group(Entities) ->
    case lists:keyfind(group, 1, Entities) of
        false -> [];
        {group, []} -> [];
        {group, GEntities} ->
            Names = lists:map(fun(Name) -> prepare_name(Name) end, GEntities),
            [" GROUP BY ", string:join(Names, ", ")]
    end.


-spec build_having(list()) -> iolist().
build_having(Conditions) ->
    case lists:keyfind(having, 1, Conditions) of
        false -> [];
        {having, []} -> [];
        {having, HConditions} ->
            H1 = lists:map(fun build_where_condition/1, HConditions),
            case lists:flatten(H1) of
                [] -> [];
                _ -> H2 = string:join(H1, " AND "),
                     [" HAVING ", H2]
            end
    end.


-spec build_order(list()) -> iolist().
build_order(Entities) ->
    case lists:keyfind(order, 1, Entities) of
        false -> [];
        {order, []} -> [];
        {order, OEntities} ->
            O = lists:map(fun(Entity) -> build_order_entity(Entity) end, OEntities),
            [" ORDER BY ", string:join(O, ", ")]
    end.


-spec build_order_entity(name() | {name(), atom()}) -> iolist().
build_order_entity({Field, asc}) -> [prepare_name(Field), " ASC"];
build_order_entity({Field, desc}) -> [prepare_name(Field), " DESC"];
build_order_entity(Field) -> [prepare_name(Field), " ASC"].


-spec build_limit(list()) -> iolist().
build_limit(Entities) ->
    lists:filtermap(fun({limit, Num}) -> {true, [" LIMIT ", integer_to_list(Num)]};
                       ({offset, N1, limit, N2}) -> {true, [" OFFSET ", integer_to_list(N1), " LIMIT ", integer_to_list(N2)]};
                       (_) -> false
                    end, Entities).


-spec build_returning(list()) -> iolist().
build_returning(Entities) ->
    case lists:keyfind(returning, 1, Entities) of
        false -> [];
        {returning, id} -> " RETURNING id";
        {returning, Names} ->
            Names2 = lists:map(fun erma_utils:prepare_name/1, Names),
            [" RETURNING ", string:join(Names2, ", ")]
    end.


-spec merge(list(), list()) -> list().
merge([], Entities2) -> Entities2;
merge(Entities1, []) -> Entities1;
merge([{Tag, Props1} | Rest], Entities2) ->
    case lists:keyfind(Tag, 1, Entities2) of
        false -> [{Tag, Props1} | merge(Rest, Entities2)];
        {Tag, Props2} -> [{Tag, Props1 ++ Props2} | merge(Rest, lists:keydelete(Tag, 1, Entities2))]
    end.
