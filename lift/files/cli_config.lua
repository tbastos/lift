------------------------------------------------------------------------------
-- CLI config management commands
------------------------------------------------------------------------------

local path = require 'lift.path'
local config = require 'lift.config'
local lstring = require 'lift.string'
local diagnostics = require 'lift.diagnostics'
local ESC = require('lift.color').ESC
local str_find = string.find

local function config_get(command)
  local key = command:consume('key')
  local value = config[key]
  if type(value) ~= 'string' then
    value = lstring.format(value)
  end
  io.write(value)
end

local function config_list(command)
  local patt = '.'
  if #command.args > 0 then
    patt = command:consume('pattern')
  end
  local write, prev_scope = io.write, nil
  config:list_vars(function(key, value, scope, overridden)
    if not str_find(key, patt) then return end -- filter by pattern
    if scope ~= prev_scope then
      write(ESC'dim', '\n-- from ', scope, ESC'clear', '\n')
      prev_scope = scope
    end
    if overridden then
      write(ESC'dim;red', tostring(key), ESC'clear',
        ESC'dim', ' (overridden)', ESC'clear', '\n')
    else
      write(ESC'red', tostring(key), ESC'clear',
        ESC'green', ' = ', ESC'clear',
        ESC'cyan', lstring.format(value), ESC'clear', '\n')
    end
  end, true)
end

local function config_edit(command)
  local sys = command.options.system.value
  local dir = sys and config.system_config_dir or config.user_config_dir
  local filename = path.from_slash(dir..'/init.lua')
  local cmd = ('%s %q'):format(config.editor, filename)
  diagnostics.report('remark: running ${1}', cmd)
  os.execute(cmd)
end

local app = ...

local config_cmd = app:command 'config'
  :desc('config', 'Configuration management subcommands')

config_cmd:command 'edit' :action(config_edit)
  :desc('config edit [-s]', 'Opens the config file in an editor')
    :flag 'system' :alias 's'
    :desc('-s, --system', "Edit the system's config file instead of the user's")

config_cmd:command 'get' :action(config_get)
  :desc('config get <key>', 'Print a config value to stdout')

config_cmd:command 'list' :action(config_list)
  :desc('config list [pattern]', 'List config variables along with their values')

