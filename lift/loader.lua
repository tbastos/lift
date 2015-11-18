------------------------------------------------------------------------------
-- Find and Load Lua Files in the ${load_path}
------------------------------------------------------------------------------

local loadfile = loadfile
local str_find = string.find

local path = require 'lift.path'
local config = require 'lift.config'
local diagnostics = require 'lift.diagnostics'

local is_dir, is_file, read_dir = path.is_dir, path.is_file, path.read_dir

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
  local i = (reverse_order and #load_path or 1)
  local dir, dir_obj, subdir, subdir_obj
  return function()
    repeat -- iterate dirs in load_path
      while dir do -- while we're in the same dir
        repeat -- iterate names in dir
          while subdir do -- while we're in the same subdir
            repeat -- iterate names in subdir
              local subname = subdir_obj:next()
              if not subname then subdir = nil break end
              local _, e, sep, sub = str_find(subname, subpatt)
              if e and (sub == '' or sep == '_') then
                local filename = subdir..'/'..subname
                if is_file(filename) then return filename end
              end
            until false
          end
          local name = dir_obj:next() ; if not name then dir = nil break end
          if name == type then
            local fullname = dir..'/'..name
            if is_dir(fullname) then
              subdir = fullname
              local _ ; _, subdir_obj = read_dir(subdir)
            end
          else
            local _, e, sep, sub = str_find(name, patt)
            if e and (sub == '' or sep == '_') then
              local filename = dir..'/'..name
              if is_file(filename) then return filename end
            end
          end
        until false
      end
      dir = load_path[i] ; if not dir then return nil end
      i = i + (reverse_order and -1 or 1)
      local _ ; _, dir_obj = read_dir(dir)
    until false
  end
end

local function _load_file(filename, ...)
  local chunk, err = loadfile(path.from_slash(filename), 't')
  if chunk then
    chunk(...)
  else
    local tb = debug.traceback(nil, 2)
    diagnostics.new{'lua_error: ${1}', err, traceback = tb}:report()
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
  local sub = subtype and ' ('..subtype..')' or ''
  diagnostics.trace('Loading '..type..sub..' scripts',
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

  -- load built-in init script
  local builtin_files = config.LIFT_SRC_DIR..'/files'
  local top_scope = _init(builtin_files..'/init.lua')

  -- load remaining init scripts in load_path
  for script in find_scripts('init', nil, true) do
    _init(script)
  end

  -- run project_file if available
  if config.project_file then
    _init(config.project_file)
  end

  -- add built-in files to the load_path
  config:insert_unique('load_path', builtin_files)

  return top_scope
end

return {
  find_scripts = find_scripts,
  init = init,
  load_all = load_all,
  load_file = load_file,
}
