package = "Lift"
version = "{{version}}-0"

source = {
{% if version == 'scm' then %}
  url = "git://github.com/tbastos/lift",
  branch = "master"
{% else %}
  url = "https://github.com/tbastos/lift/archive/v{{version}}.tar.gz",
  dir = "lift-{{version}}"
{% end %}
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
{%
  for path in modules do
    path = path:sub(#base_dir + 2, -5)
%}
    ["{{path:gsub('[/]', '.')}}"] = "{{path}}.lua",
{% end %}
  },

  install = {
    bin = {
      ['lift'] = 'bin/lift'
    }
  }
}
