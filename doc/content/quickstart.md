{
  title = 'Quickstart Guide',
  title_short = 'Quickstart',
  weight = 2,
}

## Installing Lift

Please use [LuaRocks] to install:

~~~console
$ luarocks install lift
~~~

### Prerequisites
- **OS:** Linux, OSX, Windows or another OS supported by [libuv].
- **Lua:** Lua 5.2, Lua 5.3, LuaJIT 2.0 or LuaJIT 2.1
- **Libraries:** [LPeg] and [luv] (automatically compiled by LuaRocks)

**Note:** LuaRocks uses [CMake] to build [luv]. If you have CMake installed and still get build errors, please [create an issue on GitHub](https://github.com/tbastos/lift/issues) with as much information as possible about the error.

## Sample Liftfile.lua (project-specific build script)

Create a file named `Liftfile.lua` in your project's root directory:

~~~lua
local fs = require 'lift.fs'
local task = require 'lift.task'
local config = require 'lift.config'
local request = require 'lift.request'

local function download(file_url)
  print('Downloading '..file_url)
  local filename = file_url:match('/([^/]+)$')
  request(file_url):pipe(fs.write_to(filename)):wait_finish()
  return filename
end

function task.greet() -- executed once, despite being called multiple times
  print('Hello '..(config.USER or 'unknown')..'!')
end

function task.download_lua()
  task.greet()
  print('Saved '..download('http://www.lua.org/ftp/lua-5.3.2.tar.gz'))
end

function task.download_luarocks()
  task.greet()
  print('Saved '..download('https://github.com/keplerproject/luarocks/archive/v2.3.0.tar.gz'))
end

function task.default()
  task.greet()
  task{task.download_lua, task.download_luarocks}() -- these tasks run in parallel
  print('Done!')
end

function task.clean()
  for path in fs.glob('*.tar.gz') do
    print('Deleting '..path)
    fs.unlink(path)
  end
end
~~~

Calling `lift` from any project dir will produce:

~~~console
$ lift
Hello tbastos!
Downloading http://www.lua.org/ftp/lua-5.3.2.tar.gz
Downloading https://github.com/keplerproject/luarocks/archive/v2.3.0.tar.gz
Saved lua-5.3.2.tar.gz
Saved v2.3.0.tar.gz
Done!

$ lift clean
Deleting /Users/tbastos/Work/lift/examples/downloads/lua-5.3.2.tar.gz
Deleting /Users/tbastos/Work/lift/examples/downloads/v2.3.0.tar.gz

$ lift download_lua
Hello tbastos!
Downloading http://www.lua.org/ftp/lua-5.3.2.tar.gz
Saved lua-5.3.2.tar.gz

$ lift clean greet
Hello tbastos!
Deleting /Users/tbastos/Work/lift/examples/downloads/lua-5.3.2.tar.gz
~~~

To plot a graph of task calls use (requires graphviz):
~~~console
$ lift task run --plot graph.svg
~~~

![Task call graph](http://tbastos.github.io/i/lift-examples-downloads-graph.svg)

For debugging purposes you may want to run `lift` with tracing enabled:

~~~console
$ lift --trace
[cli] running root command
[task] running task list {default} (nil)
[thread] async(function</Users/tbastos/Work/lift/examples/downloads/Liftfile.lua:30>) started
[task] running greet (nil)
[thread] async(function</Users/tbastos/Work/lift/examples/downloads/Liftfile.lua:16>) started
Hello tbastos!
[thread] async(function</Users/tbastos/Work/lift/examples/downloads/Liftfile.lua:16>) ended with true {}
[task] finished greet (nil) [0.00s]
[task] running task list {download_lua, download_luarocks} (nil)
... redacted for length ...
[task] finished task list {download_lua, download_luarocks} (nil) [4.87s]
Done!
[thread] async(function</Users/tbastos/Work/lift/examples/downloads/Liftfile.lua:30>) ended with true {}
[task] finished task list {default} (nil) [4.87s]
[cli] finished root command [4.87s]
[thread] async(function</Users/tbastos/Work/lift/bin/lift:33>) ended with true {}
Total time 4.87s, memory 603K
~~~

[CMake]: http://www.cmake.org/
[libuv]: http://libuv.org/
[luv]: https://github.com/luvit/luv
[LPeg]: http://www.inf.puc-rio.br/~roberto/lpeg/
[Lua]: http://www.lua.org/
[LuaRocks]: http://www.luarocks.org/
