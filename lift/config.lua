-------------------------------------------------------------------------------
-- Configuration System (global, transient, hierarchical key=value store)
-------------------------------------------------------------------------------
-- Gets vars from the command-line, config files and environment.

local assert, type = assert, type
local rawget, rawset, getmetatable = rawget, rawset, getmetatable
local getenv, tinsert = os.getenv, table.insert

-------------------------------------------------------------------------------
-- The immutable root scope (methods, constants, access to env vars)
-------------------------------------------------------------------------------

local env_vars = {app_id = 'lift'} -- helper table to get env vars
local root = setmetatable({}, {__index = env_vars}) -- immutable root scope
local config = {} -- the global lift.config scope

-- solve mutual dependency with lift.path
package.loaded['lift.config'] = config
local path = require 'lift.path'
local diagnostics = require 'lift.diagnostics'

-- enable access to env vars through root
setmetatable(env_vars, {__index = function(t, k)
  if type(k) ~= 'string' then return end
  -- try MYAPP_VAR_NAME first, then just var_name
  local v = getenv(config.app_id:upper().."_"..k:upper()) or getenv(k)
  if v then t[k] = v end
  return v
end})

-- forbid child scopes from shadowing root's fields
local function __newindex(t, k, v)
  if rawget(root, k) then
    error("'"..k.."' is reserved for internal use and cannot be changed")
  end
  rawset(t, k, v)
end

-- Creates a child scope that inherits from parent (default = root).
function root.new_scope(parent)
  return setmetatable({}, {__index = parent or root, __newindex = __newindex})
end

-- Changes the parent of a scope.
function root:set_parent(new_parent)
  assert(self ~= root, "the root scope's parent cannot be changed")
  assert(getmetatable(self)).__index = new_parent
end

-- Returns the parent of a scope.
function root:get_parent()
  return assert(getmetatable(self)).__index
end

-------------------------------------------------------------------------------
-- The lift.config scope (works as a proxy to its parent scope)
-------------------------------------------------------------------------------

local configMT = {__index = root:new_scope()}
configMT.__newindex = function(t, k, v)
  configMT.__index[k] = v -- write to config's parent
end
setmetatable(config, configMT)

-- Reverts lift.config to its initial state.
function root.reset()
  config:set_parent(root:new_scope())
end

-------------------------------------------------------------------------------
-- General Scope Methods
-------------------------------------------------------------------------------

-- Gets a var as a list. If the variable is a scalar it will be first converted
-- to a list. Strings are split using path.split_list(), other values are
-- simply wrapped in a table.
function root:get_list(var_name)
  local v = self[var_name] ; local tp = type(v)
  if tp == 'table' then return v end
  local t = {}
  if tp == 'string' then -- split strings
    local i = 0
    for s in path.split_list(v) do i = i + 1 ; t[i] = s end
  else -- return {v}
    t[1] = v
  end
  self[var_name] = t -- update value
  return t
end

-- Like get_list() but excludes duplicate values in the list.
function root:get_unique_list(var_name)
  local t = self:get_list(var_name)
  local mt = getmetatable(t)
  if not mt then
    mt = {[0] = 'unique'}
    setmetatable(t, mt)
    local n = 1
    for i = 1, #t do
      local v = t[i]
      if not mt[v] then
        mt[v] = true
        if n < i then t[n] = v ; t[i] = nil end
        n = n + 1
      else
        t[i] = nil
      end
    end
  else
    assert(mt[0] == 'unique', 'incompatible table')
  end
  return t, mt
end

-- Gets a var as a list and inserts a value at position pos.
-- Argument `pos` is optional and defaults to #list+1 (append).
function root:insert(list_name, value, pos)
  local t = self:get_list(list_name)
  tinsert(t, pos or (#t+1), value)
  return self
end

-- Like insert() but, if the list already contains value, it's moved to the
-- new position, instead of inserted (unless the value is being appended, in
-- which case nothing is done). In order to guarantee uniqueness, all
-- elements in the list must be inserted using this method.
function root:insert_unique(list_name, value, pos)
  local t, mt = self:get_unique_list(list_name)
  if mt[value] then
    if not pos then return self end
    for i = 1, #t do if t[i] == value then table.remove(t, i) end end
  else
    mt[value] = true
  end
  tinsert(t, pos or (#t+1), value)
  return self
end

-- Loads a config file into this scope.
function root:load(filename)
  self.self = self
  local f, err = loadfile(path.from_slash(filename), 't', self)
  if f then
    if setfenv then setfenv(f, self) end -- Lua 5.1 compatibility
    f()
  else
    local trace = debug.traceback(nil, 2)
    diagnostics.new{'lua_error: ${1}', err, traceback = trace}:report()
  end
end

-------------------------------------------------------------------------------
-- Initialization
-------------------------------------------------------------------------------

local function load_config(from_dir, filename)
  filename = path.abs(from_dir..'/'..(filename or config.config_file_name))
  if not path.is_file(filename) then return false end
  config:load(filename)
  return true
end

-- Loads all available config files based on the current ${load_path}.
-- Each file may read and overwrite variables set by previously-loaded files.
-- The first loaded file is "${LIFT_SRC_DIR}/init/config.lua" (hardcoded).
-- Files are then loaded in the reverse order of entry in ${load_path}.
-- This usually means that global configs are loaded next, then user
-- configs, then local filesystem configs (from root down to the CWD).
function root.init()
  diagnostics.trace('Loading configuration files', function()
    assert(load_config(config.LIFT_SRC_DIR, 'init/config.lua'),
      "missing Lift's built-in configuration file")
    local paths = config.load_path
    for i = #paths - 1, 1, -1 do
      load_config(paths[i])
    end
  end)
end

-- built-in constants
root._G = _G
root.LIFT_VERSION = '0.1.0'
root.LIFT_SRC_DIR = path.abs(path.dir(path.to_slash(debug.getinfo(1, "S").source:sub(2))))
root.DIR_SEPARATOR = package.config:sub(1, 1)
root.IS_WINDOWS = (root.DIR_SEPARATOR == '\\')
root.EXE_NAME = (arg and arg[0]) or '?'
assert(type(root.EXE_NAME == 'string'))

