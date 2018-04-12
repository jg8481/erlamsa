# erlamsa
Erlang port of famous radamsa fuzzzer.

## Installation:

### Installing erlang

Erlamsa requires erlang/OTP 17.5+ to run.

Download erlang from official website http://www.erlang.org, install and put in path to `erlc`, `erl` and `escript` binaries into `PATH` variable. Or use you system's packet manager to install it.

On OS X (using homebrew):
```
brew install erlang
```

On CentOS/RHEL:
```
yum install erlang
```

On Debian/Ubuntu/Kali:
```
apt-get install erlang erlang-dev erlang-tools erlang-ssl erlang-eunit erlang-mnesia erlang-inets
```

### Building

On Linux/OS X:
```
make 
```
or 
```
escript rebar co
```

On Windows (`escript.exe` and `erlc.exe` should be in `%PATH%`):
```
make_windows.bat
```

## Standalone usage: 
Under Linux/OS X use `./erlamsa`, under Windows -- `erlamsa.bat`.

Few examples/templates for a quick start:
```
$ echo 'Hello erlamsa' | ./erlamsa
Hello erlmo erlamsa
$ erlamsa <<FILE TO FUZZ>>
$ erlamsa <<FILE TO FUZZ>> -o erlamsa <<FILE TO FUZZ>>.fuzzed
$ cat <<BINARY WITH PACKET>> | ./erlamsa -o udp://<<HOST>>:<<PORT>>
```

For help try:
```
erlamsa --help
```
or
```
escript erlamsa_cmd.erl --help
```

## Using as fuzzing proxy
Erlamsa could be used a fuzzing "MiTM" proxy for TCP and UDP protocols. This allow to fuzz the communication between server and client, modifying packets coming from server to client, from client to server, or in both cases.

To use it as fuzzing proxy, run as:
```
./erlamsa -i proto://lport:[udpclientport:]rhost:rport -P probsc, probcs
```
where probsc and probcs are floats in range of 0.0 to 1.0, that represents probabilities of fuzzing packets from server to client and client to server.

E.g. erlamsa, that is started as
```
./erlamsa -i tcp://7777:192.168.0.1:7777 -P 0.1,0.9 -L -
```
will accept packets on port 7777 (on all network interfaces, basically on 0.0.0.0 interface) and send them to host's 192.168.0.1 port 7777. All packets coming from server to client will be fuzzed with probability of 10%, from client to server -- with probability of 90%. In this case, to start fuzzing just point your client application to erlamsa's host and port 7777. `-L -` options means that all logging will be output to stdout.

## Example usage from erlang code
```
-spec fuzz(binary()) -> binary().
fuzz(Data) -> 
    Opts = maps:put(paths, [direct],
            maps:put(output, return,
             maps:put(input, Data, maps:new()))),
    MutatedData = erlamsa_utils:extract_function(erlamsa_main:fuzzer(Opts)),
    MutatedData.
```

## Using as service ##

Launch as service:
```
erlamsa -H 127.0.0.1:17771
```

HTTP POST your data to `http://<Host:Port>/erlamsa/erlamsa_esi:fuzz` as `application/octet-stream`. See examples in `clients/` folder (provided for C#, node.js and python). 
E.g. for Python 2.7:
```
import httplib

erlamsa_url = '127.0.0.1:17771'

original_string = "Hello erlamsa!"

httpconn = httplib.HTTPConnection(erlamsa_url)
headers = {"content-type": "application/octet-stream"}
httpconn.request('POST', '/erlamsa/erlamsa_esi:fuzz', original_string, headers)
response = httpconn.getresponse()

fuzzed_string = response.read()

print(original_string + " erlamsed to " + fuzzed_string)
```

Result:
```
$ python clients/erlamsa_python_client.py
Hello erlamsa! erlamsed to rlamsa!rlallo eHello e
```

## External (extension) scripts

Erlamsa could use external scripts for generation-based fuzzing, custom fuzzing, custom post-fuzzing procedures or custom mutation types. Module should be compiled with `erlc` before using and passed using `-e` option to erlamsa. Due to internal mechanism of external modules inclusion, you should pass external module ALWAYS as a FIRST argument to erlamsa.

In the following example, erlamsa is run with custom mutation module (see `external_muta.erl` for details):
```
$ echo -n 123 | ./erlamsa -e external_muta -m pan=1 -p od
<pancaked>123</pancaked>
```

### Custom fuzzing extension

Could be using in fuzzing proxy mode, to replace standard fuzzing procedure with a custom one. See `external_test.erl` for example template.

### Custom mutation extension

Adds custom mutation to the list of erlamsa mutators. See `external_muta.erl` for example. 

### Custom post-processing extension

Adds post-processing procedure that will be applied to fuzzing result just before output. Useful for fixing checksum or form of data to avoid unnessesary noise. See `external_nhrp.erl` for example.

## Code Status

[![Build Status](https://travis-ci.org/Darkkey/erlamsa.svg?branch=master)](https://travis-ci.org/Darkkey/erlamsa)
