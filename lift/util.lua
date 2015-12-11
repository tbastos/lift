------------------------------------------------------------------------------
-- Utility functions (mostly to support other Lift modules)
------------------------------------------------------------------------------

local getmetatable, pairs, tostring, type = getmetatable, pairs, tostring, type
local tbl_concat, tbl_sort = table.concat, table.sort
local str_find, str_format = string.find, string.format

------------------------------------------------------------------------------
-- OS-specific constants
------------------------------------------------------------------------------

local DIR_SEP = package.config:sub(1, 1)
assert(DIR_SEP == '/' or DIR_SEP == '\\')
local UNIX = (DIR_SEP == '/') -- true on UNIX, false on Windows
local WINDOWS = (DIR_SEP ~= '/') -- true on Windows, false on UNIX

------------------------------------------------------------------------------
-- Table Key Sorting
------------------------------------------------------------------------------

local function compare_as_string(a, b)
  return tostring(a) < tostring(b)
end

local type_order = {
  number = 1,
  string = 2,
  boolean = 3,
  ['function'] = 4,
  userdata = 5,
  thread = 6,
  table = 7
}

local function compare_by_type(a, b)
  local ta, tb = type(a), type(b)
  return ta == tb and a < b or type_order[ta] < type_order[tb]
end

-- Returns a list of the keys from table t sorted according to compare.
local function keys_sorted(t, compare)
  local keys = {}
  for k in pairs(t) do
    keys[#keys+1] = k
  end
  tbl_sort(keys, compare)
  return keys
end

-- Returns a list of the keys from table t sorted by their string value.
local function keys_sorted_as_string(t)
  return keys_sorted(t, compare_as_string)
end

-- Returns a list of the keys from table t sorted by type, then value.
local function keys_sorted_by_type(t)
  return keys_sorted(t, compare_by_type)
end

------------------------------------------------------------------------------
-- Inspect (string representation of objects)
------------------------------------------------------------------------------

-- Formats an elementary value.
local function inspect_value(v, tp)
  if (tp or type(v)) == 'string' then
    return str_format('%q', v)
  else
    return tostring(v)
  end
end

-- Formats a value for indexing a table.
local function inspect_key(v)
  local tp = type(v)
  if tp == 'string' and str_find(v, '^[%a_][%w_]*$') then
    return v, true
  end
  return '['..inspect_value(v, tp)..']'
end

-- Formats a flat list of values. Returns nil if the list contains a table,
-- or if the resulting string would be longer than max_len (optional).
local function inspect_flat_list(t, max_len)
  local str, sep = '', ''
  for i = 1, #t do
    local v = t[i]
    local tp = type(v)
    if tp == 'table' then return end -- not flat!
    str = str..sep..inspect_value(v, tp)
    if max_len and #str > max_len then return end -- too long
    sep = ', '
  end
  return str
end

-- Formats a flat table. Returns nil if t contains a table, or if the
-- resulting string would be longer than max_len (optional).
local function inspect_flat_table(t, max_len, keys)
  keys = keys or keys_sorted_by_type(t)
  local str, sep = '', ''
  for i = 1, #keys do
    local k = keys[i]
    local v = t[k]
    local tp = type(v)
    if tp == 'table' then return end -- oops, not flat!
    local vs = inspect_value(v, tp)
    if k == i then
      str = str..sep..vs
    else
      str = str..sep..inspect_key(k)..' = '..vs
    end
    if max_len and #str > max_len then return end -- too long
    sep = ', '
  end
  return str
end

-- Formats anything into a string buffer. Handles tables and cycles.
local function sb_format(sb, name, t, indent, max_len)
  -- handle plain values
  local tp = type(t)
  if tp ~= 'table' then
    sb[#sb+1] = inspect_value(t, tp)
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
      inspect_flat_list(t, ml) or inspect_flat_table(t, ml, keys))
    if flat then
      sb[#sb+1] = flat
    else
      sb[#sb+1] = '\n'
      local new_indent = indent..'  '
      for i = 1, #keys do
        local k = keys[i]
        local v = t[k]
        local fk, as_id = inspect_key(k)
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

-- Formats anything into a string. Handles tables and cycles.
-- Ignores `__tostring` metamethods and treats objects as regular tables.
local function inspect_table(value, max_len)
  local sb = {}
  sb_format(sb, '@', value, '', max_len or 78)
  return tbl_concat(sb)
end

-- Formats anything into a string. Handles objects, tables and cycles.
-- Uses metamethod `__tostring` to format objects that implement it.
local function inspect(value, max_len)
  local mt = getmetatable(value)
  if mt and mt.__tostring then return tostring(value) end
  return inspect_table(value, max_len)
end

------------------------------------------------------------------------------
-- print(v) == print(inspect(v)) (use print{x, y, z} to print many values)
------------------------------------------------------------------------------

local function _print(v)
  io.write(inspect(v), '\n')
end

------------------------------------------------------------------------------
-- Module Table
------------------------------------------------------------------------------

return {
  UNIX = UNIX,
  WINDOWS = WINDOWS,
  inspect = inspect,
  inspect_flat_list = inspect_flat_list,
  inspect_flat_table = inspect_flat_table,
  inspect_key = inspect_key,
  inspect_table = inspect_table,
  inspect_value = inspect_value,
  keys_sorted = keys_sorted,
  keys_sorted_as_string = keys_sorted_as_string,
  keys_sorted_by_type = keys_sorted_by_type,
  print = _print,
}
