------------------------------------------------------------------------------
-- Initial Configurations
------------------------------------------------------------------------------

local config = ...
local path = require 'lift.path'
local lstring = require 'lift.string'

-- Current working directory
if not config.cwd then
  config.cwd = path.cwd()
end

-- Default editor
if not config.editor then
  local v = config.EDITOR
  if not v then
    v = config.IS_WINDOWS and 'notepad' or 'vi'
  end
  config.editor = v
end

-- Default project_file_names
if not config.project_file_names then
  config.project_file_names = {
    lstring.capitalize(config.APP_ID)..'file.lua',
    config.APP_ID..'file.lua',
  }
end

-- Default project_dir_name
if not config.project_files_dir_name then
  config.project_files_dir_name = '.'..config.APP_ID
end

------------------------------------------------------------------------------
-- Detect project_file and project_dir
------------------------------------------------------------------------------

(function()
  local dir = config.cwd
  repeat
    for i, name in ipairs(config.project_file_names) do
      local file = dir..'/'..name
      if path.is_file(file) then
        config.project_file = file
        config.project_dir = dir
        return
      end
    end
    if path.is_dir(dir..'/'..config.project_files_dir_name) then
      config.project_dir = dir
      return
    end
    dir = path.dir(dir)
  until #dir <= 1 or path.is_root(dir)
end)()

------------------------------------------------------------------------------
-- Portable Directory Paths: {system,user}_{config,data}_dir and cache_dir
-- We follow the XDG specification on UNIX and something sensible on Windows.
------------------------------------------------------------------------------

local function env(var_name, default_value)
  local v = var_name and os.getenv(var_name)
  return (v and path.to_slash(v)) or default_value
end

local function set_dir(name, unix_var, unix_default, win_var, win_default)
  if not config[name] then
    if config.IS_WINDOWS then
      config[name] = env(win_var, win_default) ..'/'.. config.APP_ID
    else
      config[name] = env(unix_var, unix_default) ..'/'.. config.APP_ID
    end
  end
end

local function user_home(p)
  local home = config.HOME
  return home and (home..p) or p
end

set_dir('system_config_dir',
  nil, '/etc/xdg',
  'ProgramFiles', 'c:/Program Files')

set_dir('system_data_dir',
  nil, '/usr/local/share',
  'ProgramData', 'c:/ProgramData')

set_dir('user_config_dir',
  'XDG_CONFIG_HOME', user_home('/.config'),
  'APPDATA', 'c:')

set_dir('user_data_dir',
  'XDG_DATA_HOME', user_home('/.local/share'),
  'LOCALAPPDATA', 'c:')

set_dir('cache_dir',
  'XDG_CACHE_HOME', user_home('/.cache'),
  'TEMP', 'c:/Temp')

------------------------------------------------------------------------------
-- Default load_path
------------------------------------------------------------------------------

-- Add default entries to load_path
local function add_path(p)
  if path.is_dir(p) then
    config:insert_unique('load_path', p)
    return true
  end
end

-- env vars have precedence over everything except the CLI
if config.LOAD_PATH then
  for i, dir in ipairs(config:get_list('LOAD_PATH', true)) do
    add_path(dir)
  end
end

-- project-specific files
if config.project_dir then
  add_path(config.project_dir..'/'..config.project_files_dir_name)
end

-- user and system-specific files
add_path(config.user_config_dir)
add_path(config.system_config_dir)
