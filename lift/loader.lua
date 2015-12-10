------------------------------------------------------------------------------
-- Find and Load Lua Files in the ${load_path}
------------------------------------------------------------------------------

local loadfile = loadfile
local str_find, str_match, str_sub = string.find, string.match, string.sub

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
  return function()
    -- this code is simpler with goto's
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

-- custom diagnostic for Lua syntax errors
diagnostics.levels.lua_syntax_error = 'fatal'
diagnostics.styles.lua_syntax_error = {prefix = 'syntax error:', fg = 'red'}

local load_file = diagnostics.trace('[loader] loading ${filename}',
  function(filename, ...)
    local chunk, err = loadfile(path.from_slash(filename), 't')
    if chunk then
      chunk(...)
    else
      local file, line, e = str_match(err, '^(..[^:]+):([^:]+): ()')
      file = file and path.to_slash(file)
      if file ~= filename then
        error('unexpected error format: '..err)
      end
      local msg = str_sub(err, e)
      diagnostics.new{'lua_syntax_error: ', message = msg,
        location = {file = file, line = tonumber(line)}}:report()
    end
  end)

local load_all = diagnostics.trace(
  '[loader] running all ${type} ${subtype} scripts',
  '[loader] finished all ${type} ${subtype} scripts',
  function(type, subtype, ...)
    for filename in find_scripts(type, subtype) do
      load_file(filename, ...)
    end
  end)

local function run_init(filename)
  local scope = config:new_parent(filename)
  load_file(filename, scope)
  return scope
end

-- Executes all init scripts in the ${load_path}.
-- The first loaded script is "${LIFT_SRC_DIR}/files/init.lua" (hardcoded).
-- Other scripts are then loaded in the reverse order of entry in ${load_path}.
-- This usually means that system configs are loaded next, then user configs,
-- then local filesystem (project) configs.
local init = diagnostics.trace(
  '[loader] running init scripts',
  '[loader] finished init scripts',
  function()
    local top_scope -- keep track of the top config scope
    -- run the built-in init script
    local builtin_files = config.LIFT_SRC_DIR..'/files'
    top_scope = run_init(builtin_files..'/init.lua')
    -- run all init scripts in ${load_path}
    for script in find_scripts('init', nil, true) do
      run_init(script)
    end
    -- run ${project_file} if available
    if config.project_file then
      run_init(config.project_file)
    end
    -- add built-in files to the ${load_path}
    config:insert_unique('load_path', builtin_files)
    return top_scope
  end)

return {
  find_scripts = find_scripts,
  init = init,
  load_all = load_all,
  load_file = load_file,
}
