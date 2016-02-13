#<img src="https://tbastos.github.io/i/lift.svg" height="96" align="right"/>Lift – automate tasks and create tools in Lua

[![Latest Release](https://img.shields.io/github/release/tbastos/lift.svg)](https://github.com/tbastos/lift/releases) [![Build status on UNIX](https://travis-ci.org/tbastos/lift.svg?branch=master)](https://travis-ci.org/tbastos/lift) [![Build status on Windows](https://ci.appveyor.com/api/projects/status/j15esm249a67d7f6?svg=true)](https://ci.appveyor.com/project/tbastos/lift) [![Coverage Status](https://coveralls.io/repos/tbastos/lift/badge.svg?branch=master&service=github)](https://coveralls.io/github/tbastos/lift?branch=master) [![License](http://img.shields.io/badge/License-MIT-brightgreen.svg)](LICENSE)

Lift is both a general-purpose **task automation toolkit** and a **framework for command-line tools** in Lua. It's well suited for creating build scripts, checkers, code generators, package managers, and so forth.

## Features
- **Tasks** and dependencies concisely written as Lua functions that can run in parallel.
- **Pipelines** consisting of object streams (readable, writable, duplex), pipes (flow control) and filters (transform streams).
- **Multitasking** with async/await, futures and cooperative scheduling on top of Lua coroutines.
- **Asynchronous I/O** (files, networking, IPC) and process spawning powered by [libuv].
- **Diagnostics** engine for high-quality error reporting, testing and tracing.
- Portable **filesystem operations** and `glob()` for shell-style pattern matching.
- Composable **command-line interfaces** based on command hierarchies.
- Scoped **configuration system** that gets values from the CLI, environment and Lua files.
- General-purpose [LPeg]-based parsing and AST manipulation framework.
- Text templating engine with support for embedded Lua, partials and indentation.
- Modular, extensible architecture with plugins.

### Prerequisites
- **OS:** Linux, OSX, Windows or another OS supported by [libuv].
- **Lua:** Lua 5.2, Lua 5.3, LuaJIT 2.0 or LuaJIT 2.1
- **Libraries:** [LPeg] and [luv]

## Installation

Please use [LuaRocks] to install:

```
luarocks install lift
```

## Sample Liftfile.lua

Create a file named `Liftfile.lua` at your project's root directory:

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

Calling `lift` from the root directory (where `Liftfile.lua` is located) will produce:

~~~
❯ lift
Hello tbastos!
Downloading http://www.lua.org/ftp/lua-5.3.2.tar.gz
Downloading https://github.com/keplerproject/luarocks/archive/v2.3.0.tar.gz
Saved lua-5.3.2.tar.gz
Saved v2.3.0.tar.gz
Done!

❯ lift clean
Deleting /Users/tbastos/Work/lift/examples/downloads/lua-5.3.2.tar.gz
Deleting /Users/tbastos/Work/lift/examples/downloads/v2.3.0.tar.gz

❯ lift download_lua
Hello tbastos!
Downloading http://www.lua.org/ftp/lua-5.3.2.tar.gz
Saved lua-5.3.2.tar.gz

❯ lift clean greet
Hello tbastos!
Deleting /Users/tbastos/Work/lift/examples/downloads/lua-5.3.2.tar.gz
~~~

To plot a graph of task calls use (requires graphviz):
~~~
❯ lift task run --plot graph.svg
~~~

![Task call graph](http://tbastos.github.io/i/lift-examples-downloads-graph.svg)

For debugging purposes you may want to run `lift` with tracing enabled:

~~~
❯ lift --trace
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

## Documentation

For the time being, the best documentation are the [examples](examples), the [specs](spec) and the comments in the source code (there are lots of them). This alpha release is meant for seasoned Lua programmers who are not shy to read the source code.

I'm currently working on the documentation and it'll soon be available at http://lift.run/.

## Want to contribute?

Anyone can help make this project better – follow our [contribution guidelines](CONTRIBUTING.md) and check out the [project's philosophy](CONTRIBUTING.md#philosophy).

Lift has a well-tested pure-Lua code base. You are encouraged to contribute!

## References

The following projects have in some way influenced Lift's design:

- Command-line interface: [Go], [argparse], [npm]
- Configuration: [npm], [CMake], [Vim]
- Diagnostics: [Clang]
- Task/build system: [Rake]/[Jake], [Gulp]

[argparse]: https://github.com/mpeterv/argparse
[busted]: http://olivinelabs.com/busted
[Clang]: http://clang.llvm.org/docs/InternalsManual.html
[CMake]: http://www.cmake.org/
[DSL]: http://en.wikipedia.org/wiki/Domain-specific_language
[Go]: https://golang.org/cmd/go/
[Gulp]: http://gulpjs.com/
[Jake]: http://jakejs.com/
[libuv]: http://libuv.org/
[luv]: https://github.com/luvit/luv
[LPeg]: http://www.inf.puc-rio.br/~roberto/lpeg/
[Lua]: http://www.lua.org/
[LuaRocks]: http://www.luarocks.org/
[npm]: https://www.npmjs.org/doc/
[Rake]: http://en.wikipedia.org/wiki/Rake_(software)
[Vim]: http://en.wikipedia.org/wiki/Vim_(text_editor)
