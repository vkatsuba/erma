-module(erma_utils_tests).

-include_lib("eunit/include/eunit.hrl").


%% eunit tests

valid_name_test() ->
    ?assertEqual(false, erma_utils:valid_name("user")),
    ?assertEqual(false, erma_utils:valid_name("alias")),
    ?assertEqual(false, erma_utils:valid_name("limit")),
    ?assertEqual(false, erma_utils:valid_name("like")),
    ?assertEqual(false, erma_utils:valid_name("where")),
    ?assertEqual(false, erma_utils:valid_name("123user")),
    ?assertEqual(true, erma_utils:valid_name("user123")),
    ?assertEqual(true, erma_utils:valid_name("some_user")),
    ?assertEqual(true, erma_utils:valid_name("_user")),
    ?assertEqual(false, erma_utils:valid_name("user!")),
    ?assertEqual(false, erma_utils:valid_name("user@boo")),
    ok.

prepare_name_test() ->
    ?assertEqual("`user`", erma_utils:prepare_name(user)),
    ?assertEqual("`user`", erma_utils:prepare_name("user")),
    ?assertEqual("`user`", erma_utils:prepare_name(<<"user">>)),
    ?assertEqual("`user`", erma_utils:prepare_name(["us", "er"])),
    ?assertEqual("`like`", erma_utils:prepare_name("like")),
    ?assertEqual("some_user", erma_utils:prepare_name("some_user")),
    ?assertEqual("some_user", erma_utils:prepare_name(["some", "_user"])),
    ?assertEqual("_some_other_user", erma_utils:prepare_name("_some_other_user")),
    ?assertEqual("users.id", erma_utils:prepare_name("users.id")),
    ?assertEqual("users.*", erma_utils:prepare_name("users.*")),
    ?assertEqual("`user`.id", erma_utils:prepare_name("user.id")),
    ?assertEqual("`user`.*", erma_utils:prepare_name("user.*")),
    ?assertEqual("`user`.`where`", erma_utils:prepare_name("user.where")),
    ?assertEqual("my_user.`where`", erma_utils:prepare_name("my_user.where")),
    ?assertEqual("my_user.`where`", erma_utils:prepare_name(["my_user", ".", "where"])),
    ok.

format_date_test() ->
    ?assertEqual("2014-08-05", erma_utils:format_date({2014,  8,  5})),
    ?assertEqual("2000-12-15", erma_utils:format_date({2000, 12, 15})),
    ?assertEqual("1970-10-01", erma_utils:format_date({1970, 10,  1})),
    ?assertEqual("1999-01-13", erma_utils:format_date({1999,  1, 13})),
    ?assertEqual("1873-02-08", erma_utils:format_date({1873,  2,  8})),
    ?assertEqual("1000-11-25", erma_utils:format_date({1000, 11, 25})),
    ?assertEqual("2015-09-11", erma_utils:format_date({2015,  9, 11})),
    ok.

format_time_test() ->
    ?assertEqual("00:00:00", erma_utils:format_time({ 0,  0,  0})),
    ?assertEqual("01:05:06", erma_utils:format_time({ 1,  5,  6})),
    ?assertEqual("03:11:09", erma_utils:format_time({ 3, 11,  9})),
    ?assertEqual("06:24:14", erma_utils:format_time({ 6, 24, 14})),
    ?assertEqual("10:45:36", erma_utils:format_time({10, 45, 36})),
    ?assertEqual("15:51:49", erma_utils:format_time({15, 51, 49})),
    ?assertEqual("23:59:59", erma_utils:format_time({23, 59, 59})),
    ok.

format_datetime_test() ->
    ?assertEqual("1970-01-01 12:10:00", erma_utils:format_datetime({{1970, 1, 1}, {12, 10, 0}})),
    ?assertEqual("2000-12-31 23:59:59", erma_utils:format_datetime({{2000, 12, 31}, {23, 59, 59}})),
    ?assertEqual("2014-08-05 17:34:30", erma_utils:format_datetime({{2014, 8, 5}, {17, 34, 30}})),
    ok.
