package = "lift"
version = "scm-0"

source = {
  url = "git://github.com/tbastos/lift",
  branch = "master"
}

description = {
  summary = "Lua task automation tool and scripting framework.",
  homepage = "https://lift.run",
  license = "MIT/X11",
}

dependencies = {
  'lua >= 5.2',
  'lpeg >= 1.0.0',
  'lluv >= 0.1.3',
  'luafilesystem >= 1.6.3',
}

build = {
  type = "builtin",

  modules = {
    ["lift.async"] = "lift/async.lua",
    ["lift.cli"] = "lift/cli.lua",
    ["lift.color"] = "lift/color.lua",
    ["lift.config"] = "lift/config.lua",
    ["lift.diagnostics"] = "lift/diagnostics.lua",
    ["lift.loader"] = "lift/loader.lua",
    ["lift.path"] = "lift/path.lua",
    ["lift.string"] = "lift/string.lua",
    ["lift.task"] = "lift/task.lua",
    ["lift.template"] = "lift/template.lua",
    ["lift.utils"] = "lift/utils.lua",

    ["lift.files.cli"] = "lift/files/cli.lua",
    ["lift.files.cli_config"] = "lift/files/cli_config.lua",
    ["lift.files.init"] = "lift/files/init.lua",

    ["lift.files.lift.cli_task"] = "lift/files/lift/cli_task.lua",
  },

  install = {
    bin = {
      ['lift'] = 'bin/lift'
    }
  }
}
