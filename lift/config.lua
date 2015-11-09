------------------------------------------------------------------------------
-- Configuration System (global, transient, hierarchical key=value store)
------------------------------------------------------------------------------
-- Gathers vars from the command-line, config files and environment.
-- Initial scope hierarchy: (env) <-- {root} <-- {config}

local assert, type = assert, type
local rawget, rawset, getmetatable = rawget, rawset, getmetatable
local getenv, tinsert = os.getenv, table.insert

local utils = require 'lift.utils'

------------------------------------------------------------------------------
-- The immutable root scope (methods, constants, access to env vars)
------------------------------------------------------------------------------

local env_vars = {} -- helper table to get env vars
local root = setmetatable({}, {id = 'built-in constants', __index = env_vars})
local config = {} -- the lift.config scope (a proxy)

-- solve mutual dependency with lift.path
package.loaded['lift.config'] = config
local path = require 'lift.path'
local diagnostics = require 'lift.diagnostics'

-- enable access to env vars through root
setmetatable(env_vars, {id = 'environment variables', __index = function(t, k)
  if type(k) ~= 'string' then return end
  -- try MYAPP_VAR_NAME first, then just var_name
  local v = getenv(config.APP_ID:upper().."_"..k:upper()) or getenv(k)
  if v then t[k] = v end
  return v
end})

-- root vars are immutable; forbid child scopes from shadowing them
local function __newindex(t, k, v)
  if rawget(root, k) then
    error("'"..k.."' is reserved for internal use and cannot be changed")
  end
  rawset(t, k, v)
end

-- Creates a child scope that inherits from parent (default = root).
function root.new_scope(parent, id)
  return setmetatable({}, {id = id or '?',
    __index = parent or root, __newindex = __newindex})
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

------------------------------------------------------------------------------
-- The lift.config scope (works as a proxy to its parent scope)
------------------------------------------------------------------------------

local configMT = {id = 'config proxy', __index = root}
configMT.__newindex = function(t, k, v)
  configMT.__index[k] = v -- write to config's parent
end
setmetatable(config, configMT)

------------------------------------------------------------------------------
-- Scope Methods
------------------------------------------------------------------------------

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
  local f, err = loadfile(path.from_slash(filename), 't')
  if f then
    f(self)
  else
    local trace = debug.traceback(nil, 2)
    diagnostics.new{'lua_error: ${1}', err, traceback = trace}:report()
  end
end

-- For each var call callback(key, value, scope_id, overridden).
-- This includes inherited vars but excludes constants.
-- Overridden vars are only included if `include_overridden` is true.
function root:list_vars(callback, include_overridden)
  local vars = {} -- visited vars
  local s = self -- current scope
  while true do
    local mt = getmetatable(s)
    if s ~= root then -- skip constants
      for i, k in ipairs(utils.keys_sorted_by_type(s)) do
        local visited = vars[k]
        if not visited then
          vars[k] = true
        end
        if not visited or include_overridden then
          callback(k, s[k], mt.id, visited)
        end
      end
    end
    if s == env_vars then break end
    s = mt.__index -- move to parent scope
  end
end

------------------------------------------------------------------------------
-- Module Methods
------------------------------------------------------------------------------

local function load_config(from_dir, filename)
  filename = path.abs(from_dir..'/'..(filename or config.config_file_name))
  if not path.is_file(filename) then return false end
  local scope = config:get_parent():new_scope(filename)
  scope:load(filename)
  config:set_parent(scope)
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

-- Reverts lift.config to its initial state.
-- Doesn't affect constants set through set_const().
function root.reset()
  config:set_parent(root:new_scope('cli'))
end

-- Allows apps to configure their own constants at startup.
function root.set_const(key, value)
  root[key] = value
end

------------------------------------------------------------------------------
-- Initialization
------------------------------------------------------------------------------

-- built-in immutable vars
config.set_const('APP_ID', 'lift')
config.set_const('APP_VERSION', '0.1.0')
config.set_const('LIFT_VERSION', config.APP_VERSION)
config.set_const('LIFT_SRC_DIR', path.abs(path.dir(path.to_slash(debug.getinfo(1, "S").source:sub(2)))))
config.set_const('DIR_SEPARATOR', package.config:sub(1, 1))
config.set_const('IS_WINDOWS', (root.DIR_SEPARATOR == '\\'))
config.set_const('EXE_NAME', (arg and arg[0]) or '?')
assert(type(config.EXE_NAME == 'string'))

-- finish config's initialization
config.reset()
