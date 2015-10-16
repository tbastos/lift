-------------------------------------------------------------------------------
-- Templating Engine
-------------------------------------------------------------------------------

local type = type
local assert = assert
local tostring = tostring
local setmetatable = setmetatable
local ssub = string.sub
local sfind = string.find
local tconcat = table.concat
local loadstring = loadstring or load -- Lua 5.1 compatibility

local path = require 'lift.path'

-------------------------------------------------------------------------------
-- Rewrite a template as a Lua chunk with params: writer, context, indent
-------------------------------------------------------------------------------

local tags = {
  ['{{'] = '}}', -- expressions
  ['{%'] = '%}', -- statements (at the start of line, supresses \n before it)
  ['{('] = ')}', -- includes
  ['{#'] = '#}', -- comments (at the start of line, supresses \n before it)
}

local rewriteTag = {
  ['{{'] = function(s) return '_put(_tostr('..s..'))' end,
  ['{%'] = function(s) return s end,
  ['{('] = function(s, ns)
    local name, ctx, sep = s, '_ctx', sfind(s, '<<', nil, true)
    if sep then name = ssub(s, 1, sep - 1) ; ctx = ssub(s, sep + 2) end
    return '_load('..name..', _name)(_put,'..ctx..', _ns+'..ns..')'..
      (ctx == '_ctx' and '' or '_ctx=context;') -- restore _ctx
  end,
  ['{#'] = function(s) return nil end,
}

local function rewrite_lines(c, ns, str, s, e)
  local before, after = ssub(str, s - 2, s), ssub(str, e, e + 2)
  if before == '%}\\' or before == '#}\\' then s = s + 2 end
  if after == '\n{%' or after == '\n{#' then e = e - 1 end
  while true do
    local i, j = sfind(str, '\n *', s)
    if not i or i >= e then -- last string
      if s <= e then
        c[#c + 1] = '_put[=[\n'; c[#c + 1] = ssub(str, s, e); c[#c + 1] = ']=]'
      end
      return ns
    else -- string + newline + spaces
      ns = j - i
      c[#c + 1] = '_put[=[\n'; c[#c + 1] = ssub(str, s, j); c[#c + 1] = ']=]'
      c[#c + 1] = '_put(_id)'
    end
    s = j + 1
  end
end

local function rewrite(str, name)
  assert(str, 'missing template string')
  local c = {'local _name="', name or 'unnamed',
    '";local _put,context,_ns=...;_ctx=context;',
    'local _tostr,_ns=_tostr,_ns or 0;local _id=(" "):rep(_ns);'}
  local i, j, ns = 1, 1, 0 -- ns: num spaces after last \n, -1 after indenting
  while true do
    local s, e = sfind(str, '{', i, true)
    if not s then break end
    local ts = ssub(str, s, e + 1) -- tag start
    local te = tags[ts] -- tag end; nil if ts is invalid
    if te then
      local x, y = sfind(str, te, e + 2, true)
      if x then
        if j < s then ns = rewrite_lines(c, ns, str, j, s - 1) end
        c[#c + 1] = rewriteTag[ts](ssub(str, e + 2, x - 1), ns)
        j = y + 1; i = j
      else
        name = name or str
        error("missing "..te.." to close a tag in template '"..name.."'", 2)
      end
    else
      i = s + 1
    end
  end
  rewrite_lines(c, ns, str, j, #str)
  return tconcat(c)
end

-------------------------------------------------------------------------------
-- Compile a template string into a Lua function
-------------------------------------------------------------------------------

local function to_str(x)
  if x == nil then return '' end
  if type(x) == 'function' then return to_str(x()) end
  return tostring(x)
end

local env = setmetatable({
  _ctx = '',      -- changed at the start of every template function call
  _env = {},      -- set via set_env()
  _load = '',     -- constant, set to function 'load' below
  _tostr = to_str, -- constant
}, {
  __index = function(t, k) return t._ctx[k] or t._env[k] end,
  __newindex = function(t, k, v)
    error("cannot modify context."..tostring(k)..", please declare local", 2)
  end,
})

-- given a string, return a template function f(writer, context, indent)
local setfenv = setfenv -- Lua 5.1 compatibility
local function compile(str, name)
  local source = rewrite(str, name)
  if name then name = '@'..name end
  local f, err = loadstring(source, name, 't', env)
  if err then error(err) end
  if setfenv then setfenv(f, env) end
  return f
end

local function set_env(new_env)
  env._env = new_env
end

-------------------------------------------------------------------------------
-- Loading and caching of template files
-------------------------------------------------------------------------------

local cache = {} -- {abs_filename = function}

-- resolve filename relative to abs_name or search ${load_path}
local function resolve(rel_name, abs_name)
  if path.is_abs(rel_name) then return rel_name end
  if abs_name then -- if abs_name is given we never search ${load_path}
    return path.clean(path.dir(abs_name) .. '/' .. rel_name)
  end
  local filename = path.glob('${load_path}/'..rel_name)()
  if not filename then
    error("cannot find template '"..rel_name.."'", 3)
  end
  return filename
end

-- Loads a function from a template file. If 'from' is given it should be
-- an absolute filename relative to which 'name' is resolved.
-- Otherwise search for 'name' in ${load_path}.
local function load(name, from)
  name = resolve(name, from)
  local cached = cache[name]
  if cached then return cached end
  local file = assert(io.open(name))
  local str = file:read'*a'
  if str:sub(-1, -1) == '\n' then
    -- remove the last \n from files
    str = str:sub(1, -2)
  end
  file:close()
  local func = compile(str, name)
  cache[name] = func
  return func
end

env._load = load

-------------------------------------------------------------------------------
-- Module Table
-------------------------------------------------------------------------------

local M = {
  load = load,
  cache = cache,
  compile = compile,
  set_env = set_env,
}

return M
