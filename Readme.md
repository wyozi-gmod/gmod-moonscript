https://github.com/Mijyuoon/starfall with all non-moonscript related stuff ripped out. Mijyuoon did all the work so donate/pay respect/whatever to him.

## Installation
The best way is probably using ```git clone --depth 1 https://github.com/wyozi/gmod-moonscript``` in addons folder.

## Usage
See http://moonscript.org/reference/api.html and replace all ```require``` with ```loadmodule```
```lua
local moonscript = loadmodule("moonscript.base")

local fn = moonscript.loadstring 'print "hi!"'
fn()

local code, line_table = moonscript.to_lua 'print "hi!"'
print(code, line_table)
```

## LPeg
MoonScript compiler uses LPeg. To make it have better performance copy files from gm_lpeg// to garrysmod/lua/bin/
