------------------------------------------------------------------------------
-- Utility String Manipulation Routines
------------------------------------------------------------------------------

local getmetatable, tostring, type = getmetatable, tostring, type
local str_find = string.find
local str_format = string.format
local str_gsub = string.gsub
local str_sub = string.sub
local str_upper = string.upper
local tbl_concat = table.concat
local keys_sorted_by_type = require('lift.utils').keys_sorted_by_type

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
-- String Formatting
------------------------------------------------------------------------------

-- Pretty formats an elementary value into a string.
local function format_value(v, tp)
  if (tp or type(v)) == 'string' then
    return str_format('%q', v)
  else
    return tostring(v)
  end
end

-- Pretty formats a value into a string for indexing a table.
local function format_key(v)
  local tp = type(v)
  if tp == 'string' and str_find(v, '^[%a_][%w_]*$') then
    return v, true
  end
  return '['..format_value(v, tp)..']'
end

-- Pretty formats a flat list of values into a string.
-- Returns nil if the list contains nested tables, or if the resulting
-- string would be longer than max_len (optional).
local function format_flat_list(t, max_len)
  local str, sep = '', ''
  for i = 1, #t do
    local v = t[i]
    local tp = type(v)
    if tp == 'table' then return end -- not flat!
    str = str..sep..format_value(v, tp)
    if max_len and #str > max_len then return end -- too long
    sep = ', '
  end
  return str
end

-- Pretty formats a flat table into a string.
-- Returns nil if `t` contains nested tables, or if the resulting
-- string would be longer than max_width (optional).
local function format_flat_table(t, max_len, keys)
  keys = keys or keys_sorted_by_type(t)
  local str, sep = '', ''
  for i = 1, #keys do
    local k = keys[i]
    local v = t[k]
    local tp = type(v)
    if tp == 'table' then return end -- oops, not flat!
    local vs = format_value(v, tp)
    if k == i then
      str = str..sep..vs
    else
      str = str..sep..format_key(k)..' = '..vs
    end
    if max_len and #str > max_len then return end -- too long
    sep = ', '
  end
  return str
end

-- Pretty formats any variable into a string buffer. Handles tables and cycles.
local function sb_format(sb, name, t, indent, max_len)
  -- handle plain values
  local tp = type(t)
  if tp ~= 'table' then
    sb[#sb+1] = format_value(t, tp)
    return
  end
  -- solve cycles
  if sb[t] then
    sb[#sb+1] = sb[t]
    return
  end
  -- handle nested tables
  sb[t] = name
  sb[#sb+1] = '{'
  local keys = keys_sorted_by_type(t)
  if #keys > 0 then
    local ml = max_len - #indent
    local flat = (#keys == #t and
      format_flat_list(t, ml) or format_flat_table(t, ml, keys))
    if flat then
      sb[#sb+1] = flat
    else
      sb[#sb+1] = '\n'
      local new_indent = indent..'  '
      for i = 1, #keys do
        local k = keys[i]
        local v = t[k]
        local fk, as_id = format_key(k)
        sb[#sb+1] = new_indent
        sb[#sb+1] = fk
        sb[#sb+1] = ' = '
        sb_format(sb, name..(as_id and '.'..fk or fk), v, new_indent, max_len)
        sb[#sb+1] = ',\n'
      end
      sb[#sb+1] = indent
    end
  end
  sb[#sb+1] = '}'
end

-- Pretty formats any variable into a string. Handles tables and cycles.
-- Treats objects with the __tostring metamethod as regular tables.
local function format_table(value, max_len)
  local sb = {}
  sb_format(sb, '@', value, '', max_len or 78)
  return tbl_concat(sb)
end

-- Pretty formats any variable into a string. Handles objects, tables and cycles.
-- Uses the __tostring metamethod to format objects that implement it.
local function format(value, max_len)
  local mt = getmetatable(value)
  if mt and mt.__tostring then return tostring(value) end
  return format_table(value, max_len)
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
  format = format,
  format_flat_list = format_flat_list,
  format_flat_table = format_flat_table,
  format_key = format_key,
  format_table = format_table,
  format_value = format_value,
  from_glob = from_glob,
  to_bool = to_bool,
}

return M
