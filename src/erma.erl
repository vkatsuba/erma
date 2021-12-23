-module(erma).

-export([build/1, build/2, append/2, resolve_placeholders/1, resolve_placeholders/2]).
-import(erma_utils, [
    prepare_table_name/2, prepare_name/2, prepare_value/2, prepare_limit/1, prepare_function/3
]).
-include("erma.hrl").
-ignore_xref([build/1, build/2, append/2, resolve_placeholders/1, resolve_placeholders/2]).

%%% module API

-spec build(sql_query()) -> sql().
build(Query) -> build(Query, #{database => postgresql}).


-spec build(sql_query(), erma_options()) -> sql().
build({select, Fields, Table}, Options) ->
    build_select({select, Fields, Table, []}, Options);
build({select, Fields, Table, Entities}, Options) ->
    build_select({select, Fields, Table, Entities}, Options);
build({select_distinct, Fields, Table}, Options) ->
    build_select({select_distinct, Fields, Table, []}, Options);
build({select_distinct, Fields, Table, Entities}, Options) ->
    build_select({select_distinct, Fields, Table, Entities}, Options);

build({insert, Table, Names, Values}, Options) ->
    build_insert({insert_rows, Table, Names, [Values], []}, Options);
build({insert, Table, Names, Values, Entities}, Options) ->
    build_insert({insert_rows, Table, Names, [Values], Entities}, Options);
build({insert_rows, Table, Names, Rows}, Options) ->
    build_insert({insert_rows, Table, Names, Rows, []}, Options);
build({insert_rows, Table, Names, Rows, Entities}, Options) ->
    build_insert({insert_rows, Table, Names, Rows, Entities}, Options);

build({update, Table, KV}, Options) ->
    build_update({update, Table, KV, []}, Options);
build({update, Table, KV, Entities}, Options) ->
    build_update({update, Table, KV, Entities}, Options);

build({delete, Table}, Options) ->
    build_delete({delete, Table, []}, Options);
build({delete, Table, Entities}, Options) ->
    build_delete({delete, Table, Entities}, Options).


-spec append(sql_query(), list()) -> sql_query().
append({select, Fields, Table}, NewEntities) ->
    {select, Fields, Table, merge(NewEntities, [])};
append({select, Fields, Table, Entities}, NewEntities) ->
    {select, Fields, Table, merge(NewEntities, Entities)};

append({select_distinct, Fields, Table}, NewEntities) ->
    {select_distinct, Fields, Table, merge(NewEntities, [])};
append({select_distinct, Fields, Table, Entities}, NewEntities) ->
    {select_distinct, Fields, Table, merge(NewEntities, Entities)};

append({update, Table, KV}, NewEntities) ->
    {update, Table, KV, merge(NewEntities, [])};
append({update, Table, KV, Entities}, NewEntities) ->
    {update, Table, KV, merge(NewEntities, Entities)};

append({delete, Table}, NewEntities) ->
    {delete, Table, merge(NewEntities, [])};
append({delete, Table, Entities}, NewEntities) ->
    {delete, Table, merge(NewEntities, Entities)};
append(Query, _NewEntities) -> Query.


-spec resolve_placeholders(sql_query()) -> {sql_query(), list()}.
resolve_placeholders(Query) ->
    resolve_placeholders(Query, #{database => postgresql}).


-spec resolve_placeholders(sql_query(), erma_options()) -> {sql_query(), list()}.
resolve_placeholders(Query, Options) ->
    {Query2, Params} = resolve_placeholders(Query, [], Options),
    {Query2, lists:reverse(Params)}.


-spec resolve_placeholders(term(), list(), erma_options()) -> {sql_query(), list()}.
resolve_placeholders({pl, Val}, Acc, #{database := Database}) ->
    Count = length(Acc) + 1,
    V2 = case Database of
             mysql -> "?";
             postgresql -> "$" ++ integer_to_list(Count)
         end,
    {V2, [Val | Acc]};

resolve_placeholders(Tuple, Acc, Options) when is_tuple(Tuple) ->
    {L2, Acc2} = resolve_placeholders(tuple_to_list(Tuple), Acc, Options),
    {list_to_tuple(L2), Acc2};

resolve_placeholders(List, Acc, Options) when is_list(List) ->
    {List3, Acc3} =
        lists:foldl(fun(Item, {Items, A}) ->
                            {Item2, A2} = resolve_placeholders(Item, A, Options),
                            {[Item2 | Items], A2}
                    end, {[], Acc}, List),
    {lists:reverse(List3), Acc3};

resolve_placeholders(Other, Acc, _Options) ->
    {Other, Acc}.



%%% inner functions

-spec build_select(select_query(), erma_options()) -> sql().
build_select({SelectType, Fields, Table, Entities}, #{database := Database}) ->
    Select = case SelectType of
                 select -> "SELECT ";
                 select_distinct -> "SELECT DISTINCT "
             end,
    unicode:characters_to_binary([Select, build_fields(Fields, Database), " FROM ",
        prepare_table_name(Table, Database),
        build_joins(Table, Entities, Database),
        build_where(Entities, Database),
        build_group(Entities, Database),
        build_having(Entities, Database),
        build_order(Entities, Database),
        build_limit(Entities)
    ]).


-spec build_insert(insert_query(), erma_options()) -> sql().
build_insert({_, Table, Names, Rows, Entities}, #{database := Database}) ->
    Names2 = case Names of
                 [] -> [];
                 _ ->
                     N1 = lists:map(
                         fun(Name) ->
                             prepare_name(Name, Database)
                         end, Names),
                     N2 = string:join(N1, ", "),
                     [" (", N2, ")"]
             end,
    Rows2 = lists:map(fun(V1) ->
        V2 = lists:map(fun(Value) -> erma_utils:prepare_value(Value, Database) end, V1),
        ["(", string:join(V2, ", "), ")"]
                      end, Rows),
    Rows3 = string:join(Rows2, ", "),
    unicode:characters_to_binary(["INSERT INTO ",
        prepare_table_name(Table, Database),
        Names2, " VALUES ", Rows3,
        build_returning(Entities, Database)]).


-spec build_update(update_query(), erma_options()) -> sql().
build_update({_, Table, KV, Entities}, #{database := Database}) ->
    Values = lists:map(fun({K, V}) ->
        [prepare_name(K, Database), " = ", prepare_value(V, Database)]
                       end, KV),
    Values2 = string:join(Values, ", "),
    unicode:characters_to_binary(["UPDATE ", prepare_table_name(Table, Database),
        " SET ", Values2,
        build_where(Entities, Database),
        build_returning(Entities, Database)]).


-spec build_delete(delete_query(), erma_options()) -> sql().
build_delete({_, Table, Entities}, #{database := Database}) ->
    unicode:characters_to_binary(["DELETE FROM ", prepare_table_name(Table, Database),
        build_where(Entities, Database),
        build_returning(Entities, Database)]).


-spec build_fields([field()], database()) -> iolist().
build_fields([], _) -> "*";
build_fields(Fields, Database) ->
    Fields2 = lists:map(fun({AggFun, Name, as, Alias}) ->
                                [string:to_upper(atom_to_list(AggFun)),
                                 "(", prepare_name(Name, Database), ") AS ", prepare_name(Alias, Database)];
                           ({Name, as, Alias}) ->
                                [prepare_name(Name, Database), " AS ", prepare_name(Alias, Database)];
                           ({raw, Name}) -> Name;
                           ({AggFun, Name}) ->
                                [string:to_upper(atom_to_list(AggFun)),
                                 "(", prepare_name(Name, Database), ")"];
                           ({function, Name, Arguments}) -> prepare_function(Name, Arguments, Database);
                           (Name) ->
                                prepare_name(Name, Database)
                        end, Fields),
    string:join(Fields2, ", ").


-spec build_joins(table_name(), list(), database()) -> iolist().
build_joins(MainTable, Entities, Database) ->
    case lists:keyfind(joins, 1, Entities) of
        false -> [];
        {joins, []} -> [];
        {joins, JEntities} ->
            Joins = lists:map(
                      fun({JoinType, {JoinTable, ToTable}}) ->
                             build_join_entity(JoinType, JoinTable, ToTable, [], Database);
                         ({JoinType, {JoinTable, ToTable}, Props}) ->
                             build_join_entity(JoinType, JoinTable, ToTable, Props, Database);
                         ({JoinType, JoinTable}) ->
                             build_join_entity(JoinType, JoinTable, MainTable, [], Database);
                         ({JoinType, JoinTable, Props}) ->
                             build_join_entity(JoinType, JoinTable, MainTable, Props, Database)
                      end, JEntities),
            case lists:flatten(Joins) of
                [] -> [];
                _ -> [" ", string:join(Joins, " ")]
            end
    end.


-spec build_join_entity(join_type(), table_name(), table_name(), [join_prop()], database()) -> iolist().
build_join_entity(JoinType, JoinTable, ToTable, JoinProps, Database) ->
    Join = case JoinType of
               inner -> "INNER JOIN ";
               left -> "LEFT JOIN ";
               right -> "RIGHT JOIN ";
               full -> "FULL JOIN "
           end,
    Table = prepare_table_name(JoinTable, Database),
    ToAlias = case ToTable of
                  {_, as, Alias2} -> prepare_name(Alias2, Database);
                  Name2 -> prepare_name(Name2, Database)
              end,
    {JoinName, JoinAlias} =
        case JoinTable of
            {Name3, as, Alias3} -> {Name3, prepare_name(Alias3, Database)};
            Name4 -> {Name4, prepare_name(Name4, Database)}
        end,
    PrimaryKey = case lists:keyfind(pk, 1, JoinProps) of
                     false -> "id";
                     {pk, Pk} -> prepare_name(Pk, Database)
                 end,
    ForeignKey = case lists:keyfind(fk, 1, JoinProps) of
                     false -> prepare_name([JoinName, "_id"], Database);
                     {fk, Fk} -> prepare_name(Fk, Database)
                 end,
    [Join, Table, " ON ", JoinAlias, ".", PrimaryKey, " = ", ToAlias, ".", ForeignKey].


-spec build_where(list(), database()) -> iolist().
build_where(Conditions, Database) ->
    case lists:keyfind(where, 1, Conditions) of
        false -> [];
        {where, []} -> [];
        {where, WConditions} ->
            W1 = lists:map(
                fun(WC) ->
                    build_where_condition(WC, Database)
                end, WConditions),
            case lists:flatten(W1) of
                [] -> [];
                _ -> W2 = string:join(W1, " AND "),
                     [" WHERE ", W2]
            end
    end.

-spec build_where_condition(where_condition(), database()) -> iolist().
build_where_condition({'not', WEntity}, Database) ->
    ["(NOT ", build_where_condition(WEntity, Database), ")"];
build_where_condition({'or', []}, _) -> [];
build_where_condition({'or', WConditions}, Database) ->
    W = lists:map(
        fun(WC) ->
            build_where_condition(WC, Database)
        end, WConditions),
    case W of
        [] -> [];
        _ -> ["(", string:join(W, " OR "), ")"]
    end;
build_where_condition({'and', []}, _) -> [];
build_where_condition({'and', WConditions}, Database) ->
    W = lists:map(
        fun(WC) ->
            build_where_condition(WC, Database)
        end, WConditions),
    case lists:flatten(W) of
        [] -> [];
        _ -> ["(", string:join(W, " AND "), ")"]
    end;
build_where_condition({function, Name, Arguments}, Database) ->
    prepare_function(Name, Arguments, Database);
build_where_condition({Key, '=', Value}, Database) ->
    [build_where_key(Key, Database), " = ", build_where_value(Value, Database)];
build_where_condition({Key, '<>', Value}, Database) ->
    [build_where_key(Key, Database), " <> ", build_where_value(Value, Database)];
build_where_condition({Key, '>', Value}, Database) ->
    [build_where_key(Key, Database), " > ", build_where_value(Value, Database)];
build_where_condition({Key, gt, Value}, Database) ->
    [build_where_key(Key, Database), " > ", build_where_value(Value, Database)];
build_where_condition({Key, '<', Value}, Database) ->
    [build_where_key(Key, Database), " < ", build_where_value(Value, Database)];
build_where_condition({Key, lt, Value}, Database) ->
    [build_where_key(Key, Database), " < ", build_where_value(Value, Database)];
build_where_condition({Key, '>=', Value}, Database) ->
    [build_where_key(Key, Database), " >= ", build_where_value(Value, Database)];
build_where_condition({Key, '<=', Value}, Database) ->
    [build_where_key(Key, Database), " <= ", build_where_value(Value, Database)];
build_where_condition({Key, true}, Database) ->
    [build_where_key(Key, Database), " = true"];
build_where_condition({Key, false}, Database) ->
    [build_where_key(Key, Database), " = false"];
build_where_condition({Key, like, Value}, Database) when is_list(Value) ->
    [build_where_key(Key, Database), " LIKE ", build_where_value(Value, Database)];
build_where_condition({Key, in, []}, Database) ->
    [build_where_key(Key, Database), " IN (NULL)"];
build_where_condition({Key, in, Values}, Database) when is_list(Values) ->
    V = lists:map(fun(Value) -> build_where_value(Value, Database) end, Values),
    [build_where_key(Key, Database), " IN (", string:join(V, ", "), ")"];
build_where_condition({Key, in, SubQuery}, Database) when is_tuple(SubQuery) ->
    [build_where_key(Key, Database), " IN ", build_where_value(SubQuery, Database)];
build_where_condition({Key, not_in, []}, Database) ->
    [build_where_key(Key, Database), " NOT IN (NULL)"];
build_where_condition({Key, not_in, Values}, Database) when is_list(Values) ->
    V = lists:map(fun(Value) -> build_where_value(Value, Database) end, Values),
    [build_where_key(Key, Database), " NOT IN (", string:join(V, ", "), ")"];
build_where_condition({Key, not_in, SubQuery}, Database) when is_tuple(SubQuery) ->
    [build_where_key(Key, Database), " NOT IN ", build_where_value(SubQuery, Database)];
build_where_condition({Key, is, Is}, Database) ->
    build_is(build_where_key(Key, Database), Is, Database);
build_where_condition({Key, between, Value1, Value2}, Database) ->
    [build_where_key(Key, Database), " BETWEEN ", build_where_value(Value1, Database), " AND ", build_where_value(Value2, Database)];
build_where_condition({Key, Value}, Database) ->
    [build_where_key(Key, Database), " = ", build_where_value(Value, Database)];
build_where_condition({Key, Op, Value}, Database) when is_atom(Op) ->
    [build_where_key(Key, Database), erlang:atom_to_list(Op), build_where_value(Value, Database)].

build_is(PrepKey, null, _) ->
    [PrepKey, " IS NULL"];
build_is(PrepKey, not_null, _) ->
    [PrepKey, " IS NOT NULL"];
build_is(PrepKey, {distinct_from, Val}, postgresql=Database) ->
    %% use {not, {Key, is, {distinct_from, Val}}} as equivalent for `IS NOT DISTINCT FROM`
    [PrepKey, " IS DISTINCT FROM ", build_where_value(Val, Database)];
build_is(PrepKey, {distinct_from, Val}, mysql=Database) ->
    [PrepKey, " <=> ", build_where_value(Val, Database)];
build_is(PrepKey, Bool, Database) ->
    %% use {not, {Key, is, true}} as equivalent for `IS NOT TRUE`
    [PrepKey, " IS ", build_where_value(Bool, Database)].


-spec build_where_key(where_key(), database()) -> iolist().
build_where_key({function, Name, Arguments}, Database) -> prepare_function(Name, Arguments, Database);
build_where_key(Key, Database) -> prepare_name(Key, Database).


-spec build_where_value(where_value(), database()) -> iolist().
build_where_value({select, _, _} = Query, Database) ->
    ["(", build(Query, #{database => Database}), ")"];
build_where_value({select, _, _, _} = Query, Database) ->
    ["(", build(Query, #{database => Database}), ")"];
build_where_value({select_distinct, _, _} = Query, Database) ->
    ["(", build(Query, #{database => Database}), ")"];
build_where_value({select_distinct, _, _, _} = Query, Database) ->
    ["(", build(Query, #{database => Database}), ")"];
build_where_value(Value, Database) -> prepare_value(Value, Database).


-spec build_group(list(), database()) -> iolist().
build_group(Entities, Database) ->
    case lists:keyfind(group, 1, Entities) of
        false -> [];
        {group, []} -> [];
        {group, GEntities} ->
            Names = lists:map(fun(Name) -> prepare_name(Name, Database) end, GEntities),
            [" GROUP BY ", string:join(Names, ", ")]
    end.


-spec build_having(list(), database()) -> iolist().
build_having(Conditions, Database) ->
    case lists:keyfind(having, 1, Conditions) of
        false -> [];
        {having, []} -> [];
        {having, HConditions} ->
            H1 = lists:map(
                fun(HC) ->
                    build_where_condition(HC, Database)
                end, HConditions),
            case lists:flatten(H1) of
                [] -> [];
                _ -> H2 = string:join(H1, " AND "),
                     [" HAVING ", H2]
            end
    end.


-spec build_order(list(), database()) -> iolist().
build_order(Entities, Database) ->
    case lists:keyfind(order, 1, Entities) of
        false -> [];
        {order, []} -> [];
        {order, OEntities} ->
            O = lists:map(fun(Entity) -> build_order_entity(Entity, Database) end, OEntities),
            [" ORDER BY ", string:join(O, ", ")]
    end.


-spec build_order_entity(name() | {name(), atom()}, database()) -> iolist().
build_order_entity({Field, asc}, Database) -> [prepare_name(Field, Database), " ASC"];
build_order_entity({Field, desc}, Database) -> [prepare_name(Field, Database), " DESC"];
build_order_entity(Field, Database) -> [prepare_name(Field, Database), " ASC"].


-spec build_limit(list()) -> iolist().
build_limit(Entities) ->
    lists:filtermap(
        fun({limit, Num}) ->
                {true, [" LIMIT ", prepare_limit(Num)]};
            ({offset, N1, limit, N2}) ->
                {true, [" OFFSET ", prepare_limit(N1), " LIMIT ", prepare_limit(N2)]};
            (_) -> false
        end, Entities).


-spec build_returning(list(), database()) -> iolist().
build_returning(Entities, Database) ->
    case lists:keyfind(returning, 1, Entities) of
        false -> [];
        {returning, id} -> " RETURNING id";
        {returning, Names} ->
            Names2 = lists:map(
                fun(Name) ->
                    prepare_name(Name, Database)
                end, Names),
            [" RETURNING ", string:join(Names2, ", ")]
    end.


-spec merge(list(), list()) -> list().
merge([], Acc) -> Acc;
merge([{limit, Limit} | NewEntities], Acc) ->
    merge(NewEntities, [{limit, Limit} | delete_limit(Acc)]);
merge([{offset, Offset, limit, Limit} | NewEntities], Acc) ->
    merge(NewEntities, [{offset, Offset, limit, Limit} | delete_limit(Acc)]);
merge([{Tag, Props} | NewEntities], Acc) ->
    case lists:keyfind(Tag, 1, Acc) of
        false -> merge(NewEntities, [{Tag, Props} | Acc]);
        {Tag, OldProps} ->
            Acc2 = [{Tag, OldProps ++ Props} | lists:keydelete(Tag, 1, Acc)],
            merge(NewEntities, Acc2)
    end.


-spec delete_limit(list()) -> list().
delete_limit(Entities) ->
    lists:keydelete(limit, 1, lists:keydelete(offset, 1, Entities)).
