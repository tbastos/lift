#<img src="https://tbastos.github.io/i/lift.svg" height="96" align="right"/>Lift – Lua infrastructure for tools

[![Build status on UNIX](https://travis-ci.org/tbastos/lift.svg?branch=master)](https://travis-ci.org/tbastos/lift) [![Build status on Windows](https://ci.appveyor.com/api/projects/status/j15esm249a67d7f6?svg=true)](https://ci.appveyor.com/project/tbastos/lift) [![Coverage Status](https://coveralls.io/repos/tbastos/lift/badge.svg?branch=master&service=github)](https://coveralls.io/github/tbastos/lift?branch=master) [![License](http://img.shields.io/badge/License-MIT-brightgreen.svg)](LICENSE)

Lift is both a **task automation tool** and a **framework** for writing command-line tools in Lua. It's well suited for writing build scripts, compilers, generators, checkers, and so forth.

**WARNING:** NOT READY FOR USE YET! Lift will be released soon. Interested? Leave a star! :smiley:

## Features
- Tasks and dependencies are concisely written as Lua functions and can run in parallel.
- Transparent multitasking based on coroutines and _asynchronous I/O_ (using [libuv]).
- Diagnostics engine for high-quality error reporting, tracing and testing.
- Composable command-line interfaces based on command hierarchies.
- Scoped configuration system that gets values from the CLI, environment and Lua files. 
- General-purpose [LPeg]-based parsing and AST manipulation framework.
- Text templating engine with support for embedded Lua, partials and indentation.
- Modular, extensible architecture with plugins.

### Prerequisites
- **OS:** Linux, OSX or Windows (should work on any POSIX system)
- **Lua:** Lua 5.2, Lua 5.3, LuaJIT 2.0 or LuaJIT 2.1 (LuaJIT should be
compiled with [Lua 5.2 compatibility](http://luajit.org/extensions.html))
- **Libraries:** [LPeg], [LFS] and [lluv]
 
## Installation

Install via [LuaRocks]:

    luarocks install lift

## Contributing

Lift has a straightforward, well-tested, pure-Lua code base.
You are encouraged to contribute!

Please follow the [contribution guidelines](CONTRIBUTING.md).
You may also want to read the [project's philosophy](CONTRIBUTING.md#philosophy).

## References

The following projects have in some way influenced Lift's design:

- Command-line interface: [NPM], [Thor], [argparse]
- Configuration: [NPM], [CMake], [Vim]
- Diagnostics: [Clang]
- Path API: [Go]
- Task/build system: [Rake]/[Jake], [Gulp]

[argparse]: https://github.com/mpeterv/argparse
[busted]: http://olivinelabs.com/busted
[Clang]: http://clang.llvm.org/docs/InternalsManual.html
[CMake]: http://www.cmake.org/
[DSL]: http://en.wikipedia.org/wiki/Domain-specific_language
[Go]: http://golang.org/pkg/path/filepath/
[Gulp]: http://gulpjs.com/
[Jake]: http://jakejs.com/
[LFS]: http://keplerproject.github.io/luafilesystem/
[libuv]: http://libuv.org/
[lluv]: https://github.com/moteus/lua-lluv
[LPeg]: http://www.inf.puc-rio.br/~roberto/lpeg/
[Lua]: http://www.lua.org/
[LuaRocks]: http://www.luarocks.org/
[NPM]: https://www.npmjs.org/doc/
[Rake]: http://en.wikipedia.org/wiki/Rake_(software)
[Thor]: https://github.com/erikhuda/thor/wiki
[Vim]: http://en.wikipedia.org/wiki/Vim_(text_editor)
