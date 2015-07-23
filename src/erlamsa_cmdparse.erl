% Copyright (c) 2011-2014 Aki Helin
% Copyright (c) 2014-2015 Alexander Bolshev aka dark_k3y
%
% Permission is hereby granted, free of charge, to any person obtaining a copy
% of this software and associated documentation files (the "Software"), to deal
% in the Software without restriction, including without limitation the rights
% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
% copies of the Software, and to permit persons to whom the Software is
% furnished to do so, subject to the following conditions:
%
% The above copyright notice and this permission notice shall be included in
% all copies or substantial portions of the Software.
%
% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT
% SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
% DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
% OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR
% THE USE OR OTHER DEALINGS IN THE SOFTWARE.
%
%%%-------------------------------------------------------------------
%%% @author dark_k3y
%%% @doc
%%% Cmd args parser.
%%% @end
%%%-------------------------------------------------------------------

-module(erlamsa_cmdparse).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-compile([export_all]).
-endif.

-include("erlamsa.hrl").

% API
-export([parse/1, usage/0]).

about() ->
	"Erlamsa is an erlang port of famous Radams fuzzer. Radamsa is
a general purpose fuzzer. It modifies given sample data in ways,
which might expose errors in programs intended to process the data.

Radamsa was written by Aki Helin at OUSPG.
Erlamsa is written by Alexander Bolshev (@dark_k3y).~n".

inputs() ->
	[{"filename1.txt filename2.txt ...", "data will be read from file(s) with specified name(s)"},
	{"lport:rhost:rport", "erlamsa will work in fuzzing proxy mode (currently tcp only), listenting on lport and sending fuzzed data to rhost:port"}].

outputs() ->
	[{"filename_iter%n.txt", "data will be written to files with template filename_iter%n.txt, where %n will be replaced by current interation number"},
	{"[tcp|udp]://ipaddr:port", "send fuzzed data to remote tcp or udp port located at ipaddr"},
	{"http://addr[:port]/path?params,[GET|POST],header1,...", "send fuzzed date to remote http host located at addr"}].

cmdline_optsspec() ->
	[{help		, $h, 	"help", 		undefined, 				"show this thing"},
	 {about		, $a, 	"about", 		undefined, 				"what is this thing"},
	 {version	, $V, 	"version",		undefined, 				"show program version"},
	 {input		, $i, 	"input",		string, 				"<arg>, special input, e.g. proto://lport:[udpclientport:]rhost:rport (fuzzing proxy) or :port, host:port for data input from net"},
	 {proxyprob	, $P,	"proxyprob",	{string, "0.0,0.0"},	"<arg>, fuzzing probability for proxy mode s->c,c->s"},
	 {output	, $o, 	"output",		{string, "-"}, 			"<arg>, output pattern, e.g. /tmp/fuzz-%n.foo, -, tcp://192.168.0.1:80 or udp://127.0.0.1:53 or http://example.com [-]"},
	 {count		, $n, 	"count",		{integer, 1},			"<arg>, how many outputs to generate (number or inf)"},
	 {blockscale, $b, 	"blockscale",	{float, 1.0},			"<arg>, increase/decrease default min (256 bytes) fuzzed blocksize"},
	 {sleep		, $S, 	"sleep",		{integer, 0},			"<arg>, sleep time (in ms.) between output iterations"},
	 {seed		, $s, 	"seed",			string, 				"<arg>, random seed in erlang format: int,int,int"},
	 {mutations , $m,   "mutations",	{string,
	  					 	erlamsa_mutations:tostring(	erlamsa_mutations:mutations())}, 	"<arg>, which mutations to use"},
	 {patterns	, $p,	"patterns",		{string,
	 						erlamsa_patterns:tostring(	erlamsa_patterns:patterns())},	"<arg>, which mutation patterns to use"},
	 {generators, $g,	"generators",	{string,
	 						erlamsa_gen:tostring(		erlamsa_gen:generators())},		"<arg>, which data generators to use"},
	 {meta		, $M, 	"meta",			{string, "nil"},		"<arg>, save metadata about fuzzing process to this file or stdout (-) or stderr (-err)"},
	 {logger	, $L,	"logger",		string,					"<arg>, which logger to use, e.g. file=filename"},
	 {workers	, $w, 	"workers",		{integer, 10},			"<arg>, number of workers in server mode"},
%	 {recursive , $r,	"recursive",	undefined, 				"include files in subdirectories"},
	 {verbose	, $v,	"verbose",		{integer, 0},			"be more verbose"},
	 {list		, $l,	"list",			undefined,				"list i/o options, mutations, patterns and generators"}].

usage() ->
	getopt:usage(cmdline_optsspec(), "erlamsa", "[file ...]").

fail(Reason) ->
	io:format("Error: ~s~n~n", [Reason]),
	usage(),
	halt(1).

parse_actions(List, OptionName, Default, Dict) ->
	case string_to_actions(List, atom_to_list(OptionName), Default) of
		{ok, L} ->
			maps:put(OptionName, L, Dict);
		{fail, Reason} ->
			fail(Reason)
	end.

-spec string_to_actions(string(), string(), [tuple()]) -> {ok, [tuple()]} | {fail, string()}.
string_to_actions(Lst, What, DefaultLst) ->
    Tokens = string:tokens(Lst, ","),
    Default = maps:from_list(DefaultLst),
    try
    	{ok, string_to_action_loop(lists:map(fun (X) -> string:tokens(X, "=") end, Tokens), Default, [])}
    catch
        error:badarg ->
        	{fail, "Invalid " ++ What ++ " list specification!"};
        notfound ->
        	{fail, "No such " ++ What ++ "!"}
    end.
%% TODO: check if mutation name exist
-spec string_to_action_loop([list(string())], maps:map(), list()) -> [{atom(), non_neg_integer()}].
string_to_action_loop([H|T], Default, Acc) ->
	Name = list_to_atom(hd(H)),
	Item = process_action(Name, H, maps:get(Name, Default, notfound)),
	string_to_action_loop(T, Default, [Item | Acc]);
string_to_action_loop([], _Default, Acc) -> Acc.

process_action(_Name, _, notfound) ->
	throw(notfound);
process_action(Name, [_, Pri], _DefaultPri) ->
	{Name, list_to_integer(Pri)};
process_action(Name, _, DefaultPri) ->
	{Name, DefaultPri}.

parse_logger_opts(LogOpts, Dict) ->
	case string:tokens(LogOpts, "=") of
		["file", FName] ->
			maps:put(logger_file, FName,
				maps:put(logger_type, file, Dict));
		_Else -> fail(io_lib:format("invalid logger specification: '~s'", [LogOpts]))
	end.

parse_proxyprob_opts(ProxyProbOpts, Dict) ->
	case string:tokens(ProxyProbOpts, ",") of
		[SC, CS] ->
			maps:put(proxy_probs, {list_to_float(SC), list_to_float(CS)}, Dict);
		_Else -> fail(io_lib:format("invalid proxy fuzzing probability specification: '~s'", [ProxyProbOpts]))
	end.

parse_input_opts(InputOpts, Dict) ->
	case string:tokens(InputOpts, ":") of
		[Proto, LPortD, RHost, RPort] ->
			maps:put(proxy_address, {Proto,
				list_to_integer(hd(string:tokens(LPortD, "/"))),
				?DEFAULT_UDPPROXY_CLIENTPORT,
				erlamsa_utils:resolve_addr(RHost),
				list_to_integer(RPort)},
			maps:put(mode, proxy, Dict));
		["udp", LPortD, UDPClientPort, RHost, RPort] ->
				maps:put(proxy_address, {"udp",
				list_to_integer(hd(string:tokens(LPortD, "/"))),
				UDPClientPort,
				erlamsa_utils:resolve_addr(RHost), 
				list_to_integer(RPort)},
				maps:put(mode, proxy, Dict));
		_Else -> fail(io_lib:format("invalid input specification: '~s'", [InputOpts]))
	end.


parse_sock_addr(SockType, Addr) ->
	Tokens = string:tokens(Addr, ":"),
	case length(Tokens) of
		2 ->
			{SockType, {hd(Tokens), list_to_integer(hd(tl(Tokens)))}};
		_Else ->
			fail(io_lib:format("invalid socket address specification: '~s'", [Addr]))
	end.

%% TODO: catch exception in case of incorrect...
parse_http_addr(URL) ->
	Tokens = string:tokens(URL, ","),
	{ok, {Scheme, _UserInfo, Host, Port, Path, Query}} = http_uri:parse(hd(Tokens)),
	{Scheme, {Host, Port, Path, Query, tl(Tokens)}}.

parse_url([<<"udp">>|T], _URL) ->
	parse_sock_addr(udp, binary_to_list(hd(T)));
parse_url([<<"tcp">>|T], _URL) ->
	parse_sock_addr(tcp, binary_to_list(hd(T)));
parse_url([<<"http">>|_T], URL) ->
	parse_http_addr(URL);
parse_url(_, URL) ->
	fail(io_lib:format("invalid URL specification: '~s'", [URL])).

parse_output(Output) ->
	{ok, SRe} = re:compile(":\\/\\/"),
	Tokens = re:split(Output, SRe),
	case length(Tokens) of
		1 ->
			Output; %% file or stdout
		2 ->
			parse_url(Tokens, Output); %% url
		_Else ->
			fail(io_lib:format("invalid output specification: '~s'", [Output]))
	end.

convert_metapath("nil") -> nil;
convert_metapath("stdout") -> stdout;
convert_metapath("-") -> stdout;
convert_metapath("stderr") -> stderr;
convert_metapath("-err") -> stderr;
convert_metapath(Path) -> Path.

%% TODO: seed
parse_seed_opt(Seed, Dict) ->
	try
		maps:put(seed, list_to_tuple(lists:map(fun (X) -> list_to_integer(X) end, string:tokens(Seed, ","))), Dict)
	catch
        error:badarg ->
        	fail("Invalid seed format! Usage: int,int,int")
    end.

parse(Args) ->
	case getopt:parse(cmdline_optsspec(), Args) of
		{ok, {Opts, Files}} -> parse_tokens(Opts, Files);
		_Else -> usage(), halt(-1)
	end.

parse_tokens(Opts, []) ->
	parse_opts(Opts, maps:put(paths, ["-"], maps:new()));
parse_tokens(Opts, Paths) ->
	parse_opts(Opts, maps:put(paths, Paths, maps:new())).

parse_opts([help|_T], _Dict) ->
	usage(),
	halt(0);
parse_opts([version|_T], _Dict) ->
	io:format("Erlamsa ~s~n", [?VERSION]),
	halt(0);
parse_opts([about|_T], _Dict) ->
	io:format(about(), []),
	halt(0);
parse_opts([list|_T], _Dict) ->
	Is = lists:foldl(
			fun({N, D}, Acc) ->
				[io_lib:format("    ~s: ~s~n",[N,D])|Acc]
			end
		,[], inputs()),
	Os = lists:foldl(
			fun({N, D}, Acc) ->
				[io_lib:format("    ~s: ~s~n",[N,D])|Acc]
			end
		,[], outputs()),
	Gs = lists:foldl(
			fun({N, _P, D}, Acc) ->
				[io_lib:format("    ~-6s: ~s~n",[atom_to_list(N),D])|Acc]
			end
		,[],
		lists:sort(fun ({_,N1,_}, {_,N2,_}) -> N1 =< N2 end,
			erlamsa_gen:generators())),
	Ms = lists:foldl(
			fun({_,_,_,N,D}, Acc) ->
				[io_lib:format("    ~-3s: ~s~n",[atom_to_list(N),D])|Acc]
			end
		,[],
		lists:sort(fun ({_,_,_,N1,_}, {_,_,_,N2,_}) -> N1 >= N2 end,
			erlamsa_mutations:mutations())),
	Ps = lists:foldl(
			fun({_,_,N,D}, Acc) ->
				[io_lib:format("    ~-3s: ~s~n",[atom_to_list(N),D])|Acc]
			end
		,[],
		erlamsa_patterns:patterns()),
	io:format("Inputs (-i)~n~s~nOutputs (-o)~n~s~nGenerators (-g)~n~s~nMutations (-m)~n~s~nPatterns (-p)~n~s",
		[Is, Os, Gs, Ms, Ps]),
	halt(0);
parse_opts([{verbose, Lvl}|T], Dict) ->
	parse_opts(T, maps:put(verbose, Lvl, Dict));
parse_opts([{meta, Path}|T], Dict) ->
	parse_opts(T, maps:put(metadata, convert_metapath(Path), Dict));	
parse_opts([recursive|T], Dict) ->
	parse_opts(T, maps:put(recursive, 1, Dict));
parse_opts([{count, N}|T], Dict) ->
	parse_opts(T, maps:put(n, N, Dict));
parse_opts([{blockscale, B}|T], Dict) ->
	parse_opts(T, maps:put(blockscale, B, Dict));	
parse_opts([{workers, W}|T], Dict) ->
	parse_opts(T, maps:put(workers, W, Dict));
parse_opts([{sleep, Sleep}|T], Dict) ->
	parse_opts(T, maps:put(sleep, Sleep, Dict));
parse_opts([{logger, LogOpts}|T], Dict) ->
	parse_opts(T, parse_logger_opts(LogOpts, Dict));
parse_opts([{proxyprob, ProxyProbOpts}|T], Dict) ->
	parse_opts(T, parse_proxyprob_opts(ProxyProbOpts, Dict));
parse_opts([{input, InputOpts}|T], Dict) ->
	parse_opts(T, parse_input_opts(InputOpts, Dict));
parse_opts([{mutations, Mutators}|T], Dict) ->
	parse_opts(T, parse_actions(Mutators, mutations, erlamsa_mutations:default(), Dict));
parse_opts([{patterns, Patterns}|T], Dict) ->
	parse_opts(T, parse_actions(Patterns, patterns, erlamsa_patterns:default(), Dict));
parse_opts([{generators, Generators}|T], Dict) ->
	parse_opts(T, parse_actions(Generators, generators, erlamsa_gen:default(), Dict));
parse_opts([{output, OutputOpts}|T], Dict) ->
 	parse_opts(T, maps:put(output, parse_output(OutputOpts), Dict));
parse_opts([{seed, SeedOpts}|T], Dict) ->
	parse_opts(T, parse_seed_opt(SeedOpts, Dict));
parse_opts([_|T], Dict) ->
	parse_opts(T, Dict);
parse_opts([], Dict) ->
	Dict.
