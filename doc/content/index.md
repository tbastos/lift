{
  title_short = 'Overview',
  weight = 0,
}

<img src="https://tbastos.github.io/i/lift.svg" height="96" align="right"/>

## What is Lift?

Lift is both a general-purpose **task automation tool** and a **framework for command-line tools** in Lua. It's well suited for creating build scripts, checkers, code generators, package managers and other kinds of command-line productivity tools.

## What does Lift do?

You can use Lift as a **library** to develop standalone applications _(best for control)_, or as a **scripting platform** based on the `lift` command-line tool _(best for productivity)_.

The `lift` tool gives you access to a collection of commands and tasks defined on a per-project, per-user and per-system basis. It is very flexible and allows you to leverage plugins to do almost anything.

~~~lua
local task = require 'lift.task'
local async = require 'lift.async'

function task.brush_teeth()
  print 'Brushing teeth...'
  async.sleep(2000) -- 2 seconds
  print 'Finished brushing teeth.'
end

function task.take_shower()
  print 'Taking a shower...'
  async.sleep(3000) -- 3 seconds
  print 'Finished taking a shower.'
end

function task.get_ready() -- takes 5 seconds total
  -- take a shower then brush teeth (serial execution)
  task.take_shower()
  task.brush_teeth()
  print 'Done!'
end

function task.get_ready_fast() -- takes just 3 seconds
  -- brush teeth in the shower (parallel execution)
  task{task.take_shower, task.brush_teeth}()
  print 'Done fast!'
end

task.default = task.get_ready
~~~

<script type="text/javascript" src="https://asciinema.org/a/7tmh0ivi1y020ws5dmv3j1cm4.js" id="asciicast-7tmh0ivi1y020ws5dmv3j1cm4" data-autoplay="true" data-loop="true" async></script>

## Features

- **Tasks** and dependencies concisely written as Lua functions that can run in parallel.
- **Multitasking** with async/await, futures and cooperative scheduling on top of Lua coroutines.
- **Asynchronous I/O** (files, networking, IPC) and process spawning powered by [libuv].
- **Pipelines** consisting of object streams (readable, writable, duplex), pipes (flow control) and filters (transform streams).
- **Diagnostics** engine for high-quality error reporting, testing and tracing.
- Portable **filesystem operations** and `glob()` for shell-style filename matching.
- Composable **command-line interfaces** based on command hierarchies.
- Scoped **configuration system** that gets values from the CLI, environment and Lua files.
- General-purpose [LPeg]-based parsing and AST manipulation framework.
- Text templating engine with support for embedded Lua, partials and indentation.
- Modular, extensible architecture with plugins.

[libuv]: http://libuv.org/
[LPeg]: http://www.inf.puc-rio.br/~roberto/lpeg/

## Why did you write Lift?

First, because Lua always lacked a general-purpose build/automation tool similar to Ruby's Rake/Thor, or JavaScript's Grunt/Gulp. If I needed to automate something in my C++/Lua projects I would have to resort to non-portable shell scripts, or depend on yet another language toolchain.

Second, because Lua is an excellent language for automation scripts. It's easy to pick up, supports coroutines, closures and metamethods, and its small size means it's much easier to deploy than other scripting languages. Lua-based tools can achieve exceptional levels of efficiency and portability. However, since Lua comes "without batteries", it was never an easy language to write tools in.

As a standalone tool and framework, Lift intends to solve both these problems.
I'm personally using it (as a framework) to write a development tool for C/C++, and also (as a tool) to generate this website.

In the future Lift will be available as an easy-to-deploy standalone executable independent of LuaRocks, so that you can use it to bootstrap your development environment from scratch.

