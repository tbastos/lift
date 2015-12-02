------------------------------------------------------------------------------
-- Find and Load Lua Files in the ${load_path}
------------------------------------------------------------------------------

local loadfile = loadfile
local str_find = string.find

local path = require 'lift.path'
local config = require 'lift.config'
local diagnostics = require 'lift.diagnostics'

local is_dir, is_file, scan_dir = path.is_dir, path.is_file, path.scan_dir

-- Returns an iterator over the Lua files in the ${load_path} that follow
-- a certain naming convention and match the 'type' and 'subtype' strings.
-- When subtype is omitted all subtypes are matched.
--   ./${type}.lua
--   ./${type}_${subtype}.lua
--   ./${type}/${subtype}.lua
--   ./${type}/${subtype}_*.lua
local function find_scripts(type, subtype, reverse_order)
  subtype = subtype or '[^_]*'
  local load_path = config:get_list('load_path')
  local patt = '^'..type..'(_?)('..subtype..')%.lua$'
  local subpatt = '^'..subtype..'(_?)(.*)%.lua$'
  local i, si = (reverse_order and #load_path or 1), reverse_order and -1 or 1
  local dir, dir_names, dir_i, subdir, sub_names, sub_i
  return function() -- goto's made this code simpler!
    local _, _name, _e, _sep, _sub
    if subdir then goto ITERATE_SUBDIR end
    if dir then goto ITERATE_DIR end

    ::ITERATE_LOAD_PATH:: dir = load_path[i] ; i = i + si
    if not dir then return nil end
    dir_i, dir_names = 1, scan_dir(dir)

    ::ITERATE_DIR:: _name = dir_names[dir_i] ; dir_i = dir_i + 1
      if not _name then goto ITERATE_LOAD_PATH end
      if _name == type then
        _name = dir..'/'.._name
        if is_dir(_name) then
          subdir, sub_i, sub_names = _name, 1, scan_dir(_name)
          goto ITERATE_SUBDIR
        end
      else
        _, _e, _sep, _sub = str_find(_name, patt)
        if _e and (_sub == '' or _sep == '_') then
          _name = dir..'/'.._name
          if is_file(_name) then return _name end
        end
      end
    goto ITERATE_DIR

    ::ITERATE_SUBDIR:: _name = sub_names[sub_i] ; sub_i = sub_i + 1
      if not _name then subdir = nil goto ITERATE_DIR end
      _, _e, _sep, _sub = str_find(_name, subpatt)
      if _e and (_sub == '' or _sep == '_') then
        _name = subdir..'/'.._name
        if is_file(_name) then return _name end
      end
    goto ITERATE_SUBDIR
  end
end

local function _load_file(filename, ...)
  local chunk, err = loadfile(path.from_slash(filename), 't')
  if chunk then
    chunk(...)
  else
    diagnostics.new('lua_error: ${1}', err):report()
  end
end

local function load_file(filename, ...)
  diagnostics.trace('Loading '..filename, _load_file, filename, ...)
end

local function _load_all(type, subtype, ...)
  for filename in find_scripts(type, subtype) do
    load_file(filename, ...)
  end
end

local function load_all(type, subtype, ...)
  local substr = subtype and ' ('..subtype..')' or ''
  diagnostics.trace('Running '..type..substr..' scripts',
    _load_all, type, subtype, ...)
end

local function _init(filename)
  local scope = config:new_parent(filename)
  load_file(filename, scope)
  return scope
end

-- Executes all init scripts in the ${load_path}.
-- The first loaded script is "${LIFT_SRC_DIR}/files/init.lua" (hardcoded).
-- Other scripts are then loaded in the reverse order of entry in ${load_path}.
-- This usually means that system configs are loaded next, then user configs,
-- then local filesystem (project) configs.
local function init()
  diagnostics.set_tracing(config:get_bool('tracing'))
  local top_scope
  diagnostics.trace('Running init scripts', function()
    -- run built-in init script
    local builtin_files = config.LIFT_SRC_DIR..'/files'
    top_scope = _init(builtin_files..'/init.lua')
    -- run init scripts in ${load_path}
    for script in find_scripts('init', nil, true) do
      _init(script)
    end
    -- run ${project_file} if available
    if config.project_file then
      _init(config.project_file)
    end
    -- add built-in files to the ${load_path}
    config:insert_unique('load_path', builtin_files)
  end)
  return top_scope
end

return {
  find_scripts = find_scripts,
  init = init,
  load_all = load_all,
  load_file = load_file,
}
