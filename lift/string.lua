------------------------------------------------------------------------------
-- String manipulation routines
------------------------------------------------------------------------------

local tostring, tonumber = tostring, tonumber
local str_find, str_gmatch, str_gsub = string.find, string.gmatch, string.gsub
local str_sub, str_upper = string.sub, string.upper

local WINDOWS = require'lift.util'._WINDOWS

local lpeg = require 'lpeg'
local P, R, V, Ca, Cs = lpeg.P, lpeg.R, lpeg.V, lpeg.Carg, lpeg.Cs

------------------------------------------------------------------------------
-- Basic transformations
------------------------------------------------------------------------------

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

------------------------------------------------------------------------------
-- Iterate substrings by splitting at any character in a set of delimiters
------------------------------------------------------------------------------

local DELIMITERS = (WINDOWS and ';,' or ':;,')

local function split(str, delimiters)
  delimiters = delimiters or DELIMITERS
  return str_gmatch(str, '([^'..delimiters..']+)['..delimiters..']*')
end

------------------------------------------------------------------------------
-- String-to-type conversions
------------------------------------------------------------------------------

local BOOLEANS = {
  ['1'] = true, ON = true, TRUE = true, Y = true, YES = true,
  ['0'] = false, FALSE = false, N = false, NO = false, OFF = false,
}

-- Returns true/false for well-defined bool constants, or nil otherwise
local function to_bool(str)
  return BOOLEANS[str_upper(str)]
end

-- Splits a string on ';' or ',' (or ':' on UNIX).
-- Can be used to split ${PATH}. Returns an iterator, NOT a table.
local LIST_ELEM_PATT = '([^'..DELIMITERS..']+)['..DELIMITERS..']*'
local function to_list(str)
  local t = {}
  for substr in str_gmatch(str, LIST_ELEM_PATT) do
    t[#t+1] = substr
  end
  return t
end

------------------------------------------------------------------------------
-- Line-ending conversions
------------------------------------------------------------------------------

local function lf_to_crlf(text)
  str_gsub(text, '\n', '\r\n')
end

local function crlf_to_lf(text)
  str_gsub(text, '\r\n', '\n')
end

local function native_to_lf(text)
  return WINDOWS and crlf_to_lf(text) or text
end

local function lf_to_native(text)
  return WINDOWS and lf_to_crlf(text) or text
end

------------------------------------------------------------------------------
-- Pattern-matching utilities
------------------------------------------------------------------------------

-- Escapes any "magic" character in str for use in a Lua pattern.
local function escape_magic(str)
  return (str_gsub(str, '[$^%().[%]*+-?]', '%%%1'))
end

-- Converts a basic glob pattern to a Lua pattern. Supports '*', '?'
-- and Lua-style [character classes]. Use a char class to escape: '[*]'.
local glob_to_lua = { ['^'] = '%^', ['$'] = '%$', ['%'] = '%%',
  ['('] = '%(', [')'] = '%)', ['.'] = '%.', ['['] = '%[', [']'] = '%]',
  ['+'] = '%+', ['-'] = '%-', ['?'] = '[^/]', ['*'] = '[^/]*' }
local function from_glob(glob)
  -- copy [char-classes] verbatim; translate magic chars everywhere else
  local i, res = 1, ''
  repeat
    local s, e, cclass = str_find(glob, '(%[.-%])', i)
    local before = str_sub(glob, i, s and s - 1)
    res = res..str_gsub(before, '[$^%().[%]*+-?]', glob_to_lua)..(cclass or '')
    i = e and e + 1
  until not i
  return res
end

------------------------------------------------------------------------------
-- String interpolation (recursive variable expansions using LPeg)
------------------------------------------------------------------------------

local VB, VE = P'${', P'}'
local INTEGER = R'09'^1 / tonumber
local function map_var(f, m, k)
  local v = f(m, k)
  if not v then v = '${MISSING:'..k..'}' end
  return tostring(v)
end
local Xpand = P{
  Cs( (1-VB)^0 * V'Str' * P(1)^0 ),
  Str = ( (1-VB-VE)^1 + V'Var' )^1,
  Var = Ca(1) * Ca(2) * VB * (INTEGER*VE + Cs(V'Str')*VE) / map_var
}

local function index_table(t, k) return t[k] end -- default get_var

-- Replaces '${foo}' with the result of get_var(vars, 'foo'). The key can be
-- a string or an integer. When `vars` is a table, `get_var` can be omitted.
local function expand(str, vars, get_var)
  return lpeg.match(Xpand, str, nil, get_var or index_table, vars) or str
end

------------------------------------------------------------------------------
-- Module Table
------------------------------------------------------------------------------

return {
  DELIMITERS = DELIMITERS,
  camelize = camelize,
  capitalize = capitalize,
  classify = classify,
  crlf_to_lf = crlf_to_lf,
  dasherize = dasherize,
  decamelize = decamelize,
  escape_magic = escape_magic,
  expand = expand,
  from_glob = from_glob,
  lf_to_crlf = lf_to_crlf,
  lf_to_native = lf_to_native,
  native_to_lf = native_to_lf,
  split = split,
  to_bool = to_bool,
  to_list = to_list,
}
