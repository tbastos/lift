------------------------------------------------------------------------------
-- File path manipulation routines (by string manipulation)
------------------------------------------------------------------------------

local tbl_concat = table.concat
local str_gmatch, str_match = string.gmatch, string.match
local str_gsub, str_lower, str_sub = string.gsub, string.lower, string.sub

local WINDOWS = require'lift.util'._WINDOWS

------------------------------------------------------------------------------
-- OS abstraction
------------------------------------------------------------------------------

local to_slash    -- Converts each system-specific path separator to '/'.
local from_slash  -- Converts each '/' to the system-specific path separator.
local SEP         -- Platform-specific path separator ('/' or '\')
local DELIMITER   -- Platform-specific path delimiter (':' or ';')

if WINDOWS then
  SEP, DELIMITER = '\\', ';'
  to_slash = function(path) return str_lower((str_gsub(path, SEP, '/'))) end
  from_slash = function(path) return (str_gsub(path, '/', SEP)) end
else
  SEP, DELIMITER = '/', ':'
  to_slash = function(path) return path end
  from_slash = to_slash
end

------------------------------------------------------------------------------
-- All routines below assume paths separated with '/' and case sensitive.
-- Use to_slash() when you obtain a path from outside Lift.
------------------------------------------------------------------------------

-- Returns true if the path is a FS root ('/' on UNIX, 'x:/' on Windows).
local function is_root(path)
  return path == '/' or (#path == 3 and str_match(path, '^%a:/$'))
end

-- Returns the leading volume name (for Windows paths only).
-- Given 'C:/foo' it returns 'C:'. Given '/foo' it returns ''.
local function volume(path)
  return str_match(path, '^(%a:)') or ''
end

-- Returns the last element of a path. Ignores any trailing slash.
-- Returns '.' if the path is empty, or '/' if the path is '/'.
local function base(path)
  if path == '' then return '.' end
  return str_match(path, '([^/]+)/?$') or '/'
end

-- Returns the directory part of a path (all but the last element).
-- The result has no trailing '/' unless it is the root directory.
local function dir(path)
  path = str_match(path, '^(.*)/')
  if not path then return '.' end
  if path == '' then return '/' end
  if str_sub(path, -1) == ':' then path = path .. '/' end
  return path
end

-- Returns the extension of the path, from the last '.' to the end of string
-- in the last portion of the path. Returns the empty string if there is no '.'
local function ext(path)
  return str_match(path, '%.([^./]*)$') or ''
end

-- Returns the shortest equivalent of a path by lexical processing.
-- All '//', '/./' and '/dir/../' become just '/'. The result has
-- no trailing slash unless it is the root, or if preserve_slash is true.
-- If the path is empty, returns '.' (the current working directory).
local function clean(path, preserve_trailing_slash)
  if path == '' then return '.' end
  if preserve_trailing_slash then
    if str_sub(path, -1) ~= '/' then
      path = path .. '/'
      preserve_trailing_slash = false
    end
  else path = path .. '/' end
  path = str_gsub(path, '/%./', '/')          -- '/./' to '/'
  path = str_gsub(path, '/+', '/')            -- order matters here
  path = str_gsub(path, '/[^/]+/%.%./', '/')  -- '/dir/../' to '/'
  path = str_gsub(path, '^/%.%./', '/')        -- ignore /../ at root
  if preserve_trailing_slash or is_root(path) then return path end
  return str_sub(path, 1, -2)
end

-- Returns whether path is an absolute path.
-- True if it starts with '/' on UNIX, or 'X:/' on Windows.
local function is_abs(path)
  return str_sub(path, 1, 1) == '/' or str_sub(path, 2, 2) == ':'
end

-- Resolves `path` to an absolute path. If `path` isn't already absolute, it
-- is prepended with `from` (which when not given, defaults to the cwd).
-- The resulting path is cleaned and trailing slashes are removed unless
-- `preserve_trailing_slash` is true.
local function abs(path, from, preserve_trailing_slash)
  if is_abs(path) then return path end
  if not from then from = to_slash(require'lluv'.cwd()) end
  return clean(from..'/'..path, preserve_trailing_slash)
end

-- Solves the relative path from `from` to `to`.
-- Paths must be both absolute or both relative, or an error is raised.
-- This is the reverse transform of abs(): abs(rel(from, to), from) == rel(to).
-- The resulting path is always relative on UNIX. On Windows, when paths
-- are on different volumes it's impossible to create a relative path,
-- so `to` is returned (in this case, `to` is absolute).
local function rel(from, to)
  local is_abs_from, is_abs_to = is_abs(from), is_abs(to)
  if is_abs_from ~= is_abs_to then
    error("expected two relative paths or two absolute paths", 2)
  end
  if volume(from) ~= volume(to) then
    return to -- should we raise an error instead?
  end
  from, to = clean(from), clean(to)
  if from == to then return '.' end
  -- position both iterators at the first differing elements
  local match_from = str_gmatch(from, '[^/]+')
  local match_to = str_gmatch(to, '[^/]+')
  local res, from_elem, to_elem = {}
  repeat from_elem, to_elem = match_from(), match_to()
  until from_elem ~= to_elem
  -- we go up the hierarchy while there are elements left in `from`
  while from_elem do res[#res + 1] = '..' ; from_elem = match_from() end
  -- then we go down the path to `to`
  while to_elem do
    res[#res + 1] = to_elem ; to_elem = match_to()
  end
  return tbl_concat(res, '/')
end

-- Joins any number of path elements and cleans the resulting path.
local function join(...)
  return clean(tbl_concat({...}, '/'))
end

-- Splits a path at its last separator. Returns dir, file (path = dir..file).
-- If path has no separator, returns '', path.
local function split(path)
  local d, f = str_match(path, '^(.*/)([^/]*)$')
  return d or '', f or path
end

------------------------------------------------------------------------------
-- Module Table
------------------------------------------------------------------------------

return {
  abs = abs,
  base = base,
  clean = clean,
  delimiter = DELIMITER,
  dir = dir,
  ext = ext,
  from_slash = from_slash,
  is_abs = is_abs,
  is_root = is_root,
  join = join,
  rel = rel,
  sep = SEP,
  split = split,
  to_slash = to_slash,
  volume = volume,
}
