-module(erozja_queue).
-author('baryluk@smp.if.uj.edu.pl').


-behaviour(gen_server).

-export([start/1, start_link/1, stop/1, add_item/2, get_items/1,
	stop_update/1, force_update/1, set_options/2, last_update/1]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-record(state, {url, items=[], tref=undefined, update_interval=60, last_update=0, loader_pid, loader_monitor, type, subscribed_to=[], subscribed_by=[]}).

start(URL) ->
	gen_server:start(?MODULE, {url, URL}, []).

start_link(URL) ->
	gen_server:start_link(?MODULE, {url, URL}, []).

start() ->
	gen_server:start(?MODULE, {}, []).

start_link() ->
	gen_server:start_link(?MODULE, {}, []).


stop(Pid) ->
	gen_server:cast(Pid, stop).


get_items(Pid) ->
	gen_server:call(Pid, get_items).

stop_update(Pid) ->
	gen_server:cast(Pid, stop_update).

force_update(Pid) ->
	gen_server:call(Pid, force_update).

set_options(Pid, Opts) ->
	gen_server:call(Pid, {set_options, Opts}).

last_update(Pid) ->
	gen_server:call(Pid, last_update).

% this is called by loader or subqueues
add_item(Pid, Item) ->
	gen_server:cast(Pid, {add_item, Item}).


init({url, URL}) ->
	State0 = #state{url=URL, type=feed},
	State1 = set_timer(State0),
	{ok, State1};
init({}) ->
	{ok, #state{type=agg}}.

set_timer(State = #state{tref=OldTRef, update_interval=Interval}) ->
	case OldTRef of
		undefined -> ok;
		_ ->
			{ok, cancel} = timer:cancel(OldTRef),
			ok
	end,
	{ok, TRef} = timer:send_after(Interval*1000, update_by_timer),
	State#state{tref=TRef}.

handle_call(get_items, _From, State) ->
	Items = get_items0(State),
	{reply, Items, State};

handle_call(force_update, _From, State0 = #state{type=feed}) ->
	State1 = start_update(State0),
	State2 = set_timer(State1),
	{reply, started_update, State2};

handle_call(last_update, _From, State = #state{last_update = LastUpdate}) ->
	{reply, LastUpdate, State};

handle_call(Unknown, From, State) ->
	io:format("~p: Unknown message ~p from ~p~n", [?MODULE, Unknown, From]),
	{noreply, State}.

handle_cast({add_item, Item}, State) ->
	State1 = add(Item, State),
	{noreply, State1};
handle_cast(stop, State) ->
	{stop, stop, State};
handle_cast(Unknown, State) ->
	io:format("~p: Unknown message ~p~n", [?MODULE, Unknown]),
	{noreply, State}.

start_update(State = #state{url=URL,loader_pid=undefined}) ->
	{LoaderPid, LoaderMonitor} = spawn_monitor(erozja_loader, url, [URL, self()]),
	State#state{loader_pid=LoaderPid, loader_monitor=LoaderMonitor};
start_update(State = #state{url=_URL,loader_pid=OldLoader}) when is_pid(OldLoader) ->
	State.


handle_info(update_by_timer, State0) ->
	State1 = start_update(State0),
	State2 = set_timer(State1),
	{noreply, State2};
handle_info({'DOWN', MonitorRef, process, LoaderPid, Reason}, State1 = #state{loader_pid = LoaderPid, loader_monitor=MonitorRef, url=URL}) ->
	case Reason of
		normal ->
			ok;
		_ ->
			io:format("Loader ~p for ~p down:~n Reason ~p~n", [URL, LoaderPid, Reason]),
			ok
	end,
	State2 = set_timer(State1),
	State3 = State2#state{loader_pid=undefined, loader_monitor=undefined},
	{noreply, State3};
handle_info(Msg, State) ->
	io:format("~p: Unknown message ~p~n", [?MODULE, Msg]),
	{noreply, State}.

terminate(_Reason, _State) ->
	ok.

code_change(_OldVsn, State, _Extra) ->
	{ok, State}.


get_items0(_State = #state{items=Items}) ->
	Items.

add(Item, State = #state{items=Items}) ->
	State#state{items = [Item | Items]}.
