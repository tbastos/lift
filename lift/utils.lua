------------------------------------------------------------------------------
-- Utility Functions
------------------------------------------------------------------------------

local pairs, tostring, type = pairs, tostring, type
local tbl_sort = table.sort

local function compare_as_string(a, b)
  return tostring(a) < tostring(b)
end

local function compare_by_type(a, b)
  local ta, tb = type(a), type(b)
  return ta == tb and a < b or ta < tb
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
-- Module Table
------------------------------------------------------------------------------

return {
  keys_sorted = keys_sorted,
  keys_sorted_as_string = keys_sorted_as_string,
  keys_sorted_by_type = keys_sorted_by_type,
}
