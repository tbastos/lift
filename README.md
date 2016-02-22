#<img src="https://tbastos.github.io/i/lift.svg" height="96" align="right"/>Lift – automate tasks and create tools in Lua

[![Latest Release](https://img.shields.io/github/release/tbastos/lift.svg)](https://github.com/tbastos/lift/releases) [![Build status on UNIX](https://travis-ci.org/tbastos/lift.svg?branch=master)](https://travis-ci.org/tbastos/lift) [![Build status on Windows](https://ci.appveyor.com/api/projects/status/j15esm249a67d7f6?svg=true)](https://ci.appveyor.com/project/tbastos/lift) [![Coverage Status](https://coveralls.io/repos/tbastos/lift/badge.svg?branch=master&service=github)](https://coveralls.io/github/tbastos/lift?branch=master) [![License](http://img.shields.io/badge/License-MIT-brightgreen.svg)](LICENSE)

Lift is both a general-purpose **task automation tool** and a **framework for command-line tools** in Lua. It’s well suited for creating build scripts, checkers, code generators, package managers and other kinds of command-line productivity tools.

#### Please check out <http://lift.run> to learn more!

## Contributing

Anyone can help make this project better – follow our [contribution guidelines](CONTRIBUTING.md) and check out the [project's philosophy](CONTRIBUTING.md#philosophy).

## Running Tests

Install [busted] and run `busted -v` at the root dir.

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
