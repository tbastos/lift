package = "Lift"
version = "scm-0"

source = {
  url = "git://github.com/tbastos/lift",
  branch = "master"
}

description = {
  summary = "Lua automation tool and scripting framework.",
  homepage = "http://lift.run",
  license = "MIT",
}

dependencies = {
  'lua >= 5.1', -- actually >= 5.2 or LuaJIT, but LuaJIT self-identifies as 5.1
  'lpeg >= 1.0.0',
  'luv >= 1.8.0-2',
}

build = {
  type = "builtin",

  modules = {
    ["lift.async"] = "lift/async.lua",
    ["lift.cli"] = "lift/cli.lua",
    ["lift.color"] = "lift/color.lua",
    ["lift.config"] = "lift/config.lua",
    ["lift.diagnostics"] = "lift/diagnostics.lua",
    ["lift.fs"] = "lift/fs.lua",
    ["lift.loader"] = "lift/loader.lua",
    ["lift.os"] = "lift/os.lua",
    ["lift.path"] = "lift/path.lua",
    ["lift.request"] = "lift/request.lua",
    ["lift.stream"] = "lift/stream.lua",
    ["lift.string"] = "lift/string.lua",
    ["lift.task"] = "lift/task.lua",
    ["lift.template"] = "lift/template.lua",
    ["lift.util"] = "lift/util.lua",
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