%%% @author zhongwen <zhongwencool@gmail.com>
-module(observer_cli_ets).

-include("observer_cli.hrl").

%% API
-export([start/1]).

-spec start(ViewOpts) -> no_return() when
    ViewOpts :: view_opts().
start(#view_opts{ets = #ets{interval = Interval}, auto_row = AutoRow} = ViewOpts) ->
    Pid = spawn(fun() ->
        ?output(?CLEAR),
        render_worker(Interval, undefined, AutoRow)
                end),
    manager(Pid, ViewOpts).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Private
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
manager(ChildPid, #view_opts{ets = SysOpts} = ViewOpts) ->
    case observer_cli_lib:parse_cmd(ViewOpts, ChildPid) of
        quit -> erlang:send(ChildPid, quit);
        {new_interval, NewMs} = Msg ->
            erlang:send(ChildPid, Msg),
            NewSysOpts = SysOpts#ets{interval = NewMs},
            manager(ChildPid, ViewOpts#view_opts{ets = NewSysOpts});
        _ -> manager(ChildPid, ViewOpts)
    end.

render_worker(Interval, LastTimeRef, AutoRow) ->
    TerminalRow = observer_cli_lib:get_terminal_rows(AutoRow),
    Text = "Interval: " ++ integer_to_list(Interval) ++ "ms",
    Menu = observer_cli_lib:render_menu(ets, Text, 133),
    Ets = render_ets_info(erlang:max(0, TerminalRow - 4)),
    LastLine = render_last_line(Interval),
    ?output([?CURSOR_TOP, Menu, Ets, LastLine]),
    NextTimeRef = observer_cli_lib:next_redraw(LastTimeRef, Interval),
    receive
        quit -> quit;
        {new_interval, NewMs} -> render_worker(NewMs, NextTimeRef, AutoRow);
        _ -> render_worker(Interval, NextTimeRef, AutoRow)
    end.

%% @doc List include all metrics in observer's Table Viewer.
render_ets_info(Rows) ->
    AllEtsInfo = [begin get_ets_info(Tab) end || Tab <- ets:all()],
    SorEtsInfo = lists:sort(fun(Ets1, Ets2) ->
        proplists:get_value(memory, Ets1) > proplists:get_value(memory, Ets2)
                            end, AllEtsInfo),
    Title = ?render([?UNDERLINE, ?GRAY_BG,
        ?W("Table Name", 36), ?W("Objects", 12), ?W("size", 10),
        ?W("type", 11), ?W("protection", 10), ?W("keypos", 6),
        ?W("write/read concurrency", 22), ?W("Owner Pid", 10),
        ?RESET]),
    RowView =
        [begin
             Name = get_value(name, Ets), Memory = proplists:get_value(memory, Ets),
             Size = get_value(size, Ets), Type = get_value(type, Ets),
             Protect = get_value(protection, Ets), KeyPos = get_value(keypos, Ets),
             Write = get_value(write_concurrency, Ets), Read = get_value(read_concurrency, Ets),
             Owner = get_value(owner, Ets),
             ?render([
                 ?W(Name, 36), ?W(Size, 10), ?W({byte, Memory}, 12),
                 ?W(Type, 11), ?W(Protect, 10), ?W(KeyPos, 6),
                 ?W(Write ++ "/" ++ Read, 22), ?W(Owner, 10)
             ])
         end || Ets <- lists:sublist(SorEtsInfo, Rows)],
    [Title|RowView].

render_last_line(Interval) ->
    Text = io_lib:format("i~w(Interval ~wms must >=1000ms) ", [Interval, Interval]),
    ?render([?UNDERLINE, ?RED, "INPUT:", ?RESET, ?UNDERLINE, ?GRAY_BG, "q(quit) ",
        ?W(Text, ?COLUMN - 11), ?RESET]).

get_ets_info(Tab) ->
    case catch ets:info(Tab) of
        {'EXIT', _} ->
            [{name, unread}, %%it maybe die
                {write_concurrency, unread},
                {read_concurrency, unread},
                {compressed, unread},
                {memory, 0},
                {owner, unread},
                {heir, unread},
                {size, unread},
                {node, unread},
                {named_table, unread},
                {type, unread},
                {keypos, unread},
                {protection, unread}];
        Info when is_list(Info) ->
            Owner = proplists:get_value(owner, Info),
            case is_reg(Owner) of
                Owner -> Info;
                Reg -> lists:keyreplace(Owner, 1, Info, {owner, Reg})
            end
    end.

is_reg(Owner) ->
    case process_info(Owner, registered_name) of
        {registered_name, Name} -> Name;
        _ -> Owner
    end.

get_value(Key, List) ->
    observer_cli_lib:to_list(proplists:get_value(Key, List)).
