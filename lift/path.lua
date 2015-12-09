------------------------------------------------------------------------------
-- Directory and file path manipulation routines
------------------------------------------------------------------------------

local assert, tostring, type = assert, tostring, type
local setmetatable = setmetatable
local tbl_concat = table.concat
local str_match, str_gmatch = string.match, string.gmatch
local str_sub, str_find, str_gsub = string.sub, string.find, string.gsub
local co_wrap, co_yield = coroutine.wrap, coroutine.yield
local from_glob = require('lift.string').from_glob

local config -- required at the end, to solve circular dependencies

-- OS-specific constants
local DIR_SEP = assert(package.config:sub(1, 1))
local IS_WINDOWS = (DIR_SEP == '\\')
local LIST_SEPS = (IS_WINDOWS and ';,' or ';:,')
local LIST_ELEM_PATT = '([^'..LIST_SEPS..']+)['..LIST_SEPS..']*'
local LIST_SEPS_PATT = '['..LIST_SEPS..']+'

------------------------------------------------------------------------------
-- OS abstraction functions (on top of libuv)
------------------------------------------------------------------------------

-- Converts each system-specific path separator to '/'.
local function to_slash(path)
  return DIR_SEP == '/' and path or path:gsub(DIR_SEP, '/')
end

-- Converts each '/' to the system-specific path separator.
local function from_slash(path)
  return DIR_SEP == '/' and path or path:gsub('/', DIR_SEP)
end

local uv = require 'lluv'
local uv_mkdir, uv_rmdir = uv.fs_mkdir, uv.fs_rmdir
local uv_cwd, uv_stat, uv_scandir = uv.cwd, uv.fs_stat, uv.fs_scandir

local function cwd() return to_slash(uv_cwd()) end
local function stat(path) return uv_stat(from_slash(path)) end
local function mkdir(path) return uv_mkdir(from_slash(path), 493) end -- 493 = 0755
local function rmdir(path) return uv_rmdir(from_slash(path)) end
local function scan_dir(path) return uv_scandir(from_slash(path)) end

------------------------------------------------------------------------------
-- Routines for manipulating slash-separated paths
------------------------------------------------------------------------------

-- Returns true if path is a filesystem root.
local function is_root(path)
  return path == '/' or (#path == 3 and str_match(path, '^%a:/$'))
end

-- Returns the leading volume name (for Windows paths).
-- Given 'C:/foo' it returns 'C:'. Given '/foo' it returns ''.
local function volume_name(path)
  return str_match(path, '^(%a:)') or ''
end

-- Returns the last element of path. Trailing slashes are removed before
-- extracting the last element. If the path is empty, returns '.'.
-- If the path consists entirely of slashes, returns '/'.
local function base(path)
  if path == '' then return '.' end
  return str_match(path, '([^/]+)/?$') or '/'
end

-- Returns all but the last element of path, typically the path's directory.
-- The result does not end in a separator unless it is the root directory.
local function dir(path)
  path = str_match(path, '^(.*)/')
  if not path then return '.' end
  if path == '' then return '/' end
  if str_sub(path, -1) == ':' then path = path .. '/' end
  return path
end

-- Returns the filename extension (the string after the last dot of the
-- last element) of path, or '' if there is no dot.
local function ext(path)
  return str_match(path, '%.([^./]*)$') or ''
end

-- Returns the shortest equivalent of path by lexical processing.
-- All '//', '/./' and '/dir/../' become just '/'. The result only
-- ends in a slash if it is the root '/', or if preserve_slash is true.
-- When the result is empty, clean() returns '.'.
local function clean(path, preserve_trailing_slash)
  if path == '' then return '.' end
  if preserve_trailing_slash then
    if str_sub(path, -1) ~= '/' then
      path = path .. '/'
      preserve_trailing_slash = false
    end
  else path = path .. '/' end
  path = str_gsub(path, '/%./', '/')    -- '/./' to '/'
  path = str_gsub(path, '/+', '/')           -- order matters here
  path = str_gsub(path, '/[^/]+/%.%./', '/') -- '/dir/../' to '/'
  path = str_gsub(path, '/../', '/') -- ignore /../ at the root
  if preserve_trailing_slash or is_root(path) then return path end
  return str_sub(path, 1, -2)
end

-- Returns true if the path is absolute.
local function is_abs(path)
  return str_sub(path, 1, 1) == '/' or
    (IS_WINDOWS and str_sub(path, 2, 2) == ':')
end

-- Returns an absolute representation of path. If the path is not
-- absolute it will be prepended with abs_path; if abs_path is not
-- given, the current working directory will be used.
local function abs(path, abs_path, preserve_trailing_slash)
  if is_abs(path) then return path end
  if not abs_path then abs_path = assert(cwd()) end
  return clean(abs_path .. '/' .. path, preserve_trailing_slash)
end

-- Returns a relative path that is lexically equivalent to target when
-- joined to base. That is, join(base, rel(base, target)) is equivalent
-- to target itself. The returned path will always be relative to base,
-- even if base and target share no elements. If target can't be made
-- relative to base, or if knowing the cwd would be necessary to compute it.
local function rel(base_path, target)
  base_path, target = clean(base_path), clean(target)
  if base_path == target then return '.' end
  -- position both iterators at the first differing elements
  local match_base = str_gmatch(base_path, '[^/]+')
  local match_target = str_gmatch(target, '[^/]+')
  local res, base_elem, target_elem = {}
  repeat base_elem, target_elem = match_base(), match_target()
  until base_elem ~= target_elem
  -- if there are base elements left, we go up the hierarchy
  while base_elem do res[#res + 1] = '..' ; base_elem = match_base() end
  -- finally, we add the remaining target elements
  if target_elem == '.' then error("result depends on current dir", 2) end
  while target_elem do
    res[#res + 1] = target_elem ; target_elem = match_target()
  end
  return tbl_concat(res, '/')
end

-- Joins any number of path elements and cleans the result.
local function join(...)
  return clean(tbl_concat({...}, '/'))
end

-- Splits path immediately following the final separator, separating it
-- into a (dir, file) tuple. If there is no separator in path, returns
-- ('', path). The returned values have the property that path=dir..file.
local function split(path)
  local d, f = str_match(path, '^(.*/)([^/]*)$')
  return d or '', f or path
end

-- Splits a list of paths joined by OS-specific separators (such as used
-- in the PATH environment variable). Returns an iterator, NOT a table.
local function split_list(path, t)
  return str_gmatch(path, LIST_ELEM_PATT)
end

-- Returns true if path exists and is a directory.
local function is_dir(path)
  local t = stat(path)
  return t and t.is_directory or false
end

-- Returns true if path exists and is a file.
local function is_file(path)
  local t = stat(path)
  return t and t.is_file or false
end

-- Creates a directory named `path` along with any necessary parents.
local function _mkdir_all(path)
  if not is_dir(path) then
    _mkdir_all(dir(path)) -- create ancestors
    return mkdir(path)
  end
end
local function mkdir_all(path)
  path = clean(path)
  local ok, err = _mkdir_all(path)
  return (ok and path), err -- clean path on success, nil + err otherwise
end

------------------------------------------------------------------------------
-- Globbing: shell-style glob patterns and n-fold ${variable} expansions
------------------------------------------------------------------------------
-- Supports wildcards (**/, *, ?, [cclass]) and n-fold ${var} expansions.
-- A '**' matches 0 or more directories. It must adjoin '/'s, as in '**/'.
-- A '*' matches 0 or more characters (but never '/').
-- A '?' matches any single character (but not '/').
-- A [cclass] matches a character in the set (use [^...] for set complement).
--   Caveat: the character '/' cannot be included in a [cclass].
-- All ${variables} are expanded and matched as plain strings (no patterns).
-- Special case: if ${var} is a list, each element is tested to match the path.

-- default get_var
local function index_table(t, k) return t[k] end 

-- Creates a path pattern table from a `glob` string.
-- A pattern table is a list where each elem is either a string or a list.
local function glob_parse(glob, vars, get_var)
  vars, get_var = vars or config, get_var or index_table
  local pt, n, i = {}, 0, 1 -- pattern table, #pt, pos in glob
  local lstr -- last added string (or nil if pt[n] is not a string)
  while true do
    local s, e, name = str_find(glob, '${([^}]+)}', i)
    if not s or i < s then -- add string before ${var}, or the last string
      local str = str_sub(glob, i, s and s - 1)
      if str ~= '' then
        if lstr then lstr = lstr..str ; pt[n] = lstr -- append to prev string
        else n = n + 1 ; pt[n] = str ; lstr = str end -- or add new element
      end
      if not s then return pt end
    end
    local v = get_var(vars, name)
    if not v then error('no such variable ${'..name..'}', 2) end
    -- if the var is a string containing LIST_SEPS, convert it to a list
    if type(v) == 'string' and str_find(v, LIST_SEPS_PATT) then
      local list, li = {}, 0
      for str in split_list(v) do li = li + 1 ; list[li] = str end
      v = list
    end
    local vt = type(v)
    if vt == 'table' and #v == 1 then v, vt = v[1], nil end
    if vt == 'table' then
      n = n + 1 ; pt[n] = v ; lstr = nil
    else
      v = tostring(v or '{empty}')
      if lstr then lstr = lstr..v ; pt[n] = lstr -- append to prev string
      else n = n + 1 ; pt[n] = v ; lstr = v end -- or add new element
    end
    i = e + 1
  end
end

-- Computes all possible expansions of the pattern table 'pt' (the product
-- of its list variables) and calls callback(arg, str) with each string.
-- Stops and returns the first truthy result from callback.
local function _product(pt, t, i, n, callback, arg)
  while i <= n do
    local v = pt[i]
    local vt = type(v)
    if vt == 'table' then
      for k = 1, #v do
        t[i] = v[k]
        local res = _product(pt, t, i + 1, n, callback, arg)
        if res then return res end
      end
      return
    end
    i = i + 1
  end
  return callback(tbl_concat(t), arg)
end
local function glob_product(pt, callback, arg)
  local n = #pt
  if n == 1 and type(pt[1]) == 'string' then -- optimization
    return callback(pt[1], arg)
  end
  local t = {} ; for i = 1, n do t[i] = pt[i] end
  return _product(pt, t, 1, n, callback, arg)
end

-- Returns whether the `path` string matches the `glob` pattern.
local function match_alternative(pattern, path)
  pattern = (str_gsub(from_glob(pattern), '%[^/]%*%[^/]%*/', '.*/')) -- handle **/
  return str_match(path, '^'..pattern..'$') ~= nil
end
local function match(path, glob, vars, get_var)
  local pt = glob_parse(glob, vars, get_var)
  return glob_product(pt, match_alternative, path) or false
end

-- metatable to memoize scan_dir()
local DirEntries = {__index = function(t, path)
  local res = scan_dir(path) or false
  t[path] = res
  return res
end}

-- visits all subdirs of path calling f on them
local function glob_starstar(f, path, dir_entries, ...)
  f(path, dir_entries, ...)
  local names = dir_entries[path]
  for i = 1, #names do
    local name = names[i]
    if str_find(name, '^%.') == nil then -- ignore dot files
      local p = path..'/'..names[i]
      if is_dir(p) then
        glob_starstar(f, p, dir_entries, ...)
      end
    end
  end
end

-- processes the glob pattern recursively while visiting matches
local function glob_recurse(path, dir_entries, pattern, init, len)
  -- find the next path segment containing a pattern
  local s, e, patt = str_find(pattern, '([^/]*[[*?][^/]*)', init)
  path = path..str_sub(pattern, init, s and s - 1) -- expand path to just before patt
  if not s then
    -- no more patterns, check if this path exists...
    if stat(path) then co_yield(path) end
    return
  end
  -- scan files in current path
  local names = dir_entries[path]
  if not names then return end -- not a dir, give up this path
  e = e + 1
  if patt == '**' then -- starstar: match any number of subdirs
    if e >= len then error("expected a name or pattern after wildcard '**'", 0) end
    path = str_sub(path, 1, -2) -- remove trailing slash
    dir_entries[path] = names -- optimization
    return glob_starstar(glob_recurse, path, dir_entries, pattern, e, len)
  end
  -- ignore dot files unless patt begins with a dot (ex: $HOME/.*/file)
  local ignore_dot = (str_sub(patt, 1, 1) ~= '.')
  patt = (ignore_dot and '^(%.?)' or '^')..from_glob(patt)..'$'
  for i = 1, #names do
    local name = names[i]
    local matched, _, dot = str_find(name, patt)
    if matched and dot ~= '.' then
      if e < len then -- pattern continues
        glob_recurse(path..name, dir_entries, pattern, e, len)
      else -- pattern ends here, and this is a match
        co_yield(path..name)
      end
    end
  end
end

-- called for all combinations of vars, with a complete pattern string
local function glob_alternative(pattern, dir_entries)
  local base_dir = is_abs(pattern) and '' or ((config.cd or cwd())..'/')
  glob_recurse(base_dir, dir_entries, pattern, 1, #pattern)
end

-- Finds all pathnames that match the glob pattern. Returns an iterator
-- that produces an absolute path (or nil) each time it's called.
local function glob(pattern, vars, get_var)
  local pt = glob_parse(pattern, vars, get_var)
  return co_wrap(function()
    glob_product(pt, glob_alternative, setmetatable({}, DirEntries))
  end)
end

------------------------------------------------------------------------------
-- Initialization
------------------------------------------------------------------------------

local M = {
  abs = abs,
  base = base,
  clean = clean,
  cwd = cwd,
  dir = dir,
  ext = ext,
  from_slash = from_slash,
  glob = glob,
  glob_parse = glob_parse,
  glob_product = glob_product,
  is_abs = is_abs,
  is_dir = is_dir,
  is_file = is_file,
  is_root = is_root,
  join = join,
  match = match,
  mkdir = mkdir,
  mkdir_all = mkdir_all,
  rel = rel,
  rmdir = rmdir,
  scan_dir = scan_dir,
  split = split,
  split_list = split_list,
  to_slash = to_slash,
  volume_name = volume_name,
}

-- solve mutual dependency with lift.config
package.loaded['lift.path'] = M
config = require 'lift.config'

