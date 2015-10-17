#<img src="https://tbastos.github.io/i/lift.svg" height="96" align="right"/>Lift – Write powerful tools in Lua

[![Build status on UNIX](https://travis-ci.org/tbastos/lift.svg?branch=master)](https://travis-ci.org/tbastos/lift) [![Build status on Windows](https://ci.appveyor.com/api/projects/status/j15esm249a67d7f6?svg=true)](https://ci.appveyor.com/project/tbastos/lift) [![Coverage Status](https://coveralls.io/repos/tbastos/lift/badge.svg?branch=master)](https://coveralls.io/r/tbastos/lift?branch=master) [![License](http://img.shields.io/badge/License-MIT-brightgreen.svg)](LICENSE)

Lift is both a build tool (**task runner**) and a **framework** for writing CLI tools in Lua. It's well suited for writing compilers, generators, checkers, and so forth.

**WARNING:** PROJECT IS NOT READY YET! It will be announced soon. Interested? Leave a star! :smiley:

## Features

- Tasks can be defined declaratively or written imperatively as Lua functions (best of both worlds).
- Efficient multitasking engine with support for _asynchronous I/O_ and _process-level concurrency_.
- Diagnostics engine for high-quality error reporting, tracing and testing.
- Command-line interface and application configuration framework.
- General-purpose [LPeg]-based parsing and AST manipulation framework.
- Text templating engine with support for embedded Lua, partials and indentation.
- Modular, extensible architecture.

### Prerequisites
- **OS:** Linux, OSX or Windows (should work on any POSIX system)
- **Lua:** 5.1, 5.2 or 5.3 (or a compatible LuaJIT)
- **Libraries:** [LFS], [LPeg]
 
## Installation

Install via [LuaRocks]:

    luarocks install lift

## Contributing

Lift has a straightforward, well-tested, pure-Lua code base. You are encouraged to contribute! Please follow the [contribution guidelines](CONTRIBUTING.md).

## References

The following projects have in some way influenced Lift's design:

- Command-line interface: [NPM], [Thor], [argparse]
- Configuration: [NPM], [CMake], [Vim]
- Diagnostics: [Clang]
- Path API: [Go]
- Task/Build engine: [Rake]/[Jake], [Tup]

[argparse]: https://github.com/mpeterv/argparse
[busted]: http://olivinelabs.com/busted
[Clang]: http://clang.llvm.org/docs/InternalsManual.html
[CMake]: http://www.cmake.org/
[DSL]: http://en.wikipedia.org/wiki/Domain-specific_language
[Go]: http://golang.org/pkg/path/filepath/
[Jake]: http://jakejs.com/docs
[LFS]: http://keplerproject.github.io/luafilesystem/
[LPeg]: http://www.inf.puc-rio.br/~roberto/lpeg/
[Lua]: http://www.lua.org/
[LuaRocks]: http://www.luarocks.org/
[NPM]: https://www.npmjs.org/doc/
[Rake]: http://en.wikipedia.org/wiki/Rake_(software)
[Thor]: https://github.com/erikhuda/thor/wiki
[Tup]: http://gittup.org/tup
[Vim]: http://en.wikipedia.org/wiki/Vim_(text_editor)
