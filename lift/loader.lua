------------------------------------------------------------------------------
-- Find and Load Lua Files in the ${load_path}
------------------------------------------------------------------------------

local ipairs, loadfile = ipairs, loadfile
local str_find = string.find

local path = require 'lift.path'
local config = require 'lift.config'
local diagnostics = require 'lift.diagnostics'

local is_dir, is_file, read_dir = path.is_dir, path.is_file, path.read_dir

-- Returns an iterator over the Lua files in the ${load_path} that follow
-- a certain naming convention and match the 'type' and 'subtype' strings.
-- The subtype defaults to '.*' when omitted, so all subtypes are matched.
--   ./${type}.lua
--   ./${type}_${subtype}.lua
--   ./${type}/${subtype}.lua
--   ./${type}/${subtype}_*.lua
local function find_scripts(type, subtype, reverse_order)
  subtype = subtype or '.*'
  local t, load_path = {}, config:get_list('load_path')
  local patt, subpatt = '^'..type..'(_?).-%.lua$', '^'..subtype..'(_?).-%.lua$'
  local start, limit, step = 1, #load_path, 1
  if reverse_order then
    start, limit, step = limit, start, -1
  end
  for i = start, limit, step do
    local base_dir = load_path[i]
    for name in read_dir(base_dir) do
      if name == type and is_dir(name) then
        local subdir = base_dir..'/'..name
        for subname in read_dir(subdir) do
          local _, e, sep = str_find(subtype, subpatt)
          if e and (sep == '' or sep == '_') then
            t[#t+1] = subdir..'/'..subname
          end
        end
      else
        local _, e, sep = str_find(name, patt)
        if e and (sep == '' or sep == '_') then
          local filename = base_dir..'/'..name
          if is_file(filename) then
            t[#t+1] = filename
          end
        end
      end
    end
  end
  return t
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
  for i, filename in ipairs(find_scripts(type, subtype)) do
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
  local builtin_files = config.LIFT_SRC_DIR..'/files'
  local top_scope = _init(builtin_files..'/init.lua')

  for i, script in ipairs(find_scripts('init', nil, true)) do
    _init(script)
  end
  config:insert_unique('load_path', builtin_files)

  return top_scope
end

return {
  find_scripts = find_scripts,
  init = init,
  load_all = load_all,
  load_file = load_file,
}
