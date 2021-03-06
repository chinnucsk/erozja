-module(erozja_loader).
-author('baryluk@smp.if.uj.edu.pl').


-export([url/1, url/2]).

-include("erozja.hrl").

% TODO: check if we are not in offline mode

url(URL = "http://" ++ _) ->
	url_real(URL);
url(URL = "https://" ++ _) ->
	url_real(URL);
url("file://" ++ FileName) ->
	url_file(FileName);
url(_) ->
	bad_url.

url_real(URL) ->
	?deb("starting request to~n", [URL]),
	% TODO: ask manager to if we can start (to limit number of concurrant connections)
	% TODO: parse and send data to queue, as we download data from internet, abort if we are downloading to long or to large,
	% or feed format is invalid, or for example single item is much to large, or there is to many items
	FetchResult = httpc:request(get, {URL, []}, [{timeout, 60000}, {connect_timeout, 30000}], [{body_format, binary}]),
	try FetchResult of
		{ok, {{_, 200, _}, _Headers, Body}} ->
			?deb("ended request to~n", [URL]),
			ParingResult = erozja_parse:string(Body),
			ParingResult;
		E = {error, timeout} ->
			E;
		E = {error, {connect_failed, nxdomain}} ->
			E
	catch
		error:E ->
			{error, E}
	end.

url_file(FileName) ->
	try file:read_file(FileName) of
		{ok, Body} ->
			ParingResult = erozja_parse:string(Body),
			ParingResult;
		E ->
			E
	catch
		error:E ->
			{error, E}
	end.


url(URL, ParentQueue) ->
	case url(URL) of
		{ok, Items} ->
			?deb("fetched ~p items~n", [length(Items)]),
			lists:foreach(fun(Item) ->
				erozja_queue:add_item(ParentQueue, Item)
			end, Items),
			%erozja_queue:loader_done(ParentQueue, ok),
			ok;
		Other ->
			%erozja_queue:loader_done(ParentQueue, Other)
			exit(Other) % this will be send using monitor nicely
	end,
	ok.
