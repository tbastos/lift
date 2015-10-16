package = "lift"
version = "scm-0"

source = {
  url = "git://github.com/tbastos/lift",
  branch = "master"
}

description = {
  summary = "Lua task runner and CLI tool development framework.",
  homepage = "https://lift.run/",
  license = "MIT/X11",
}

dependencies = {
  "lua >= 5.1",
  'lpeg >= 1.0.0',
  'luafilesystem >= 1.6.3',
}

build = {
  type = "builtin",

  modules = {
    ["lift.cli"] = "lift/cli.lua",
    ["lift.color"] = "lift/color.lua",
    ["lift.config"] = "lift/config.lua",
    ["lift.diagnostics"] = "lift/diagnostics.lua",
    ["lift.path"] = "lift/path.lua",
    ["lift.string"] = "lift/string.lua",
    ["lift.task"] = "lift/task.lua",
    ["lift.template"] = "lift/template.lua",

    ["lift.init.config"] = "lift/init/config.lua",
  },

  install = {
    bin = {
      ['lift'] = 'bin/lift'
    }
  }
}
