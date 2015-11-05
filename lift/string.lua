------------------------------------------------------------------------------
-- Utility String Manipulation Routines
------------------------------------------------------------------------------

local tostring, type = tostring, type
local str_find = string.find
local str_gsub = string.gsub
local str_sub = string.sub
local str_upper = string.upper

-- Returns the Capitalized form of a string
local function capitalize(str)
  return (str_gsub(str, '^%l', str_upper))
end

-- Returns the camelCase form of a string keeping the 1st word unchanged
local function camelize(str)
  return (str_gsub(str, '%W+(%w+)', capitalize))
end

-- Returns the UpperCamelCase form of a string
local function classify(str)
  return (str_gsub(str, '%W*(%w+)', capitalize))
end

-- Separates a camelized string by underscores, keeping capitalization
local function decamelize(str)
  return (str_gsub(str, '(%l)(%u)', '%1_%2'))
end

-- Replaces each word separator with a single dash
local function dasherize(str)
  return (str_gsub(str, '%W+', '-'))
end

local BOOLEANS = {
  ['1'] = true, ON = true, TRUE = true, Y = true, YES = true,
  ['0'] = false, FALSE = false, N = false, NO = false, OFF = false,
}

-- Returns true/false for well-defined bool constants, or nil otherwise
local function to_bool(str)
  return BOOLEANS[str_upper(str)]
end

-- Escapes any "magic" character in str for use in a Lua pattern.
local function escape_magic(str)
  return (str_gsub(str, '[$^%().[%]*+-?]', '%%%1'))
end

-- Converts a file 'globbing' pattern to a Lua pattern. Supports '*',
-- '?' and Lua-style [] character sets. Does not support escaping.
local magic_translation = { ['^'] = '%^', ['$'] = '%$', ['%'] = '%%',
  ['('] = '%(', [')'] = '%)', ['.'] = '%.', ['['] = '%[', [']'] = '%]',
  ['+'] = '%+', ['-'] = '%-', ['?'] = '[^/]', ['*'] = '[^/]*' }
local function from_glob(glob)
  -- copy [] char sets verbatim; translate magic chars everywhere else
  local init, res = 1, ''
  while init do
    local s, e, cs = str_find(glob, '(%[.-%])', init)
    local str = str_sub(glob, init, s and s - 1)
    res = res..str_gsub(str, '[$^%().[%]*+-?]', magic_translation)..(cs or '')
    init = e and e + 1
  end
  return res
end

------------------------------------------------------------------------------
-- String Interpolation
------------------------------------------------------------------------------

-- expander: helper function that converts single-digit string indices
-- tonumber() and returns all valid values converted tostring().
local digits, _env = {}, nil
for i = 1, 9 do digits[tostring(i)] = i end
local function expander(k)
  local v = _env[(digits[k] or k)] ; return v and tostring(v)
end

-- Expands ${vars} using a mapping function or table
local function expand(str, map)
  local previous = _env
  if type(map) ~= 'function' then _env, map = map, expander end
  str = str_gsub(str, '%${([^}]+)}', map)
  _env = previous
  return str
end

-- Expands all list elements in-place, automatically converting
-- non-string elements to string. Returns the same list.
local function expand_list(list, map)
  local previous = _env
  if type(map) ~= 'function' then _env, map = map, expander end
  for i = 1, #list do
    list[i] = str_gsub(tostring(list[i]), '%${([^}]+)}', map)
  end
  _env = previous
  return list
end

------------------------------------------------------------------------------
-- Module Table
------------------------------------------------------------------------------

local M = {
  camelize = camelize,
  capitalize = capitalize,
  classify = classify,
  dasherize = dasherize,
  decamelize = decamelize,
  escape_magic = escape_magic,
  expand = expand,
  expand_list = expand_list,
  from_glob = from_glob,
  to_bool = to_bool,
}

return M
