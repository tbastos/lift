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

## Why did you write Lift?

I wrote Lift for a few reasons. First, Lua lacked a general-purpose build/automation tool similar to Ruby's Rake, or JavaScript's Jake/Grunt/Gulp. If I needed to automate anything in my C/C++/Lua projects I would have to resort to non-portable shell scripts, or depend on yet another toolchain such as `npm`. Since Lua itself lacks batteries, it was never a convenient language to write portable tools in. Lift comes to solve these problems by being both an automation tool and a tool framework.

Lua is actually an excellent language for tools. It's easy to pick up, has features such as coroutines and metamethods (which JavaScript lacks), and its small size means it's much easier to deploy than other scripting languages. Lift provides unique value as a small, extensible framework for tools. It's _not_ specialized for one class of applications (such as building native vs. web applications), and almost any use case can be covered by leveraging plugins.

Personally, I'm using Lift to write a C/C++ dev tool. And also to generate this website.

In the future Lift will be available as an easy-to-deploy standalone executable that does not depend on LuaRocks, so that you can use it to bootstrap your development environment from scratch.

