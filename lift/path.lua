------------------------------------------------------------------------------
-- Directory and File Path Manipulation Routines
------------------------------------------------------------------------------

local assert, load, tostring, type = assert, load, tostring, type
local unpack = table.unpack or unpack -- LuaJIT compatibility
local tbl_concat = table.concat
local str_match, str_gmatch = string.match, string.gmatch
local str_sub, str_find, str_gsub = string.sub, string.find, string.gsub
local from_glob = require('lift.string').from_glob

-- bypass mutual dependency with lift.config
local config

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

local Dir = {}
Dir.__index = Dir
function Dir:next() local i = self.i or 0; i = i + 1; self.i = i; return self[i] end
function Dir:close() end

local function scan_dir(path)
  -- TODO rewrite glob using coroutines and libuv
  -- this is temporary hack (adapter)
  return setmetatable(uv_scandir(from_slash(path)), Dir)
end

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

-- Recursively creates the set of nested directories defined by path.
-- Does not throw an error if any of the dirs already exists.
local function _make(path)
  if not is_dir(path) then
    _make(dir(path)) -- make ancestors
    return mkdir(path)
  end
end
local function make(path)
  path = clean(path)
  local ok, err = _make(path)
  return (ok and path), err -- clean path on success, or nil + err
end

-- Returns true if path matches the glob pattern.
local function match(path, glob)
  if not glob then error('missing glob pattern', 2) end
  return str_match(path, '^'..from_glob(glob)..'$') ~= nil
end

------------------------------------------------------------------------------
-- Globbing patterns with ${var} expansion and n-fold ${list} products
------------------------------------------------------------------------------
-- Based on auto-generated "closure" iterator factories for efficiency.
-- Each factory handles a pattern with a specific number of components.
-- A component is either: a string, a list, or a glob pattern.

local function next_s(str, state) return state, nil end
local function next_l(list, i)
  if i >= #list then return end
  i = i + 1 ; return list[i], i
end
local function next_p(patt, dir_obj)
  ::start::
  local s = dir_obj:next() if not s then dir_obj:close() return end
  if s ~= '.' and s ~= '..' and match(s, patt) then return s, dir_obj end
  goto start
end

-- returns an iterator and initial state for a component c
local function init(c, t, i) -- i = number of valid elements in t
  -- on well-formed dir paths, test if dir exists
  local path ; if i > 0 and str_sub(t[i], -1) == '/' then
    path = tbl_concat(t, '', 1, i)
    if not is_dir(path) then return path, nil end
  end
  if type(c) == 'table' then return next_l, 0 end -- list
  if str_find(c, '[*?[]') then -- pattern
    local dir_obj = scan_dir(path) ; return next_p, dir_obj
  end
  return next_s, c -- string
end

local function globber_factory(n)
  local t = {'local init, stat, abs, concat, t'}
  for i = 1, n do t[#t + 1] = ', c'..i end
  for i = 1, n do t[#t + 1] = ', f'..i..', s'..i end
  t[#t + 1] = ' = ...\nreturn function() local v repeat\n'
  for i = n, 1, -1 do t[#t + 1] = 'repeat while not s'..i..' do\n' end
  t[#t + 1] = 'if f1 then return nil end\n'
  for i = 1, n do
    t[#t + 1] = 'f'..i..', s'..i..' = init(c'..i..', t, '..(i - 1)..
      ') end v, s'..i..' = f'..i..'(c'..i..', s'..i..') until v t['..
      i..'] = '..(i > 1 and 'v' or 'abs(v, nil, true)')..'\n'
  end
  t[#t + 1] = 'v = concat(t) until stat(v) return v end'
  return assert(load(tbl_concat(t), '=globber_factory('..n..')'))
end

local cache = {}
function cache:__index(n)
  local f = globber_factory(n)
  self[n] = f ; return f
end
cache = setmetatable(cache, cache)

-- adds a str to the list t; if last elem is a string, appends str to it
local function add_str(t, n, lstr, str)
  if lstr then lstr = lstr .. str ; t[n] = lstr ; return n, lstr end
  n = n + 1 ; t[n] = str ; return n, str
end

-- Returns an iterator over the files matching the glob pattern.
-- Supports patterns such as '/${list}/*/bin/lua*'. The input pattern
-- can be absolute or relative. Returned filenames are always absolute.
local function glob(pattern, env, enable_debug)
  local match_var, match_patt_elem = '%${([^}]+)}', '([^/]*[*?[][^/]*)'
  local t, n, i, lstr = {}, 0, 1 -- template list, #t, position in pattern
  local sv, ev, name = str_find(pattern, match_var, i)
  local sp, ep, patt = str_find(pattern, match_patt_elem, i)
  while true do
    local s -- s = min(sv, sp) or whichever is available
    if not sv then if not sp then break else s = sp end
    else if not sp then s = sv else s = (sv < sp and sv or sp) end end
    if s == sp then -- pattern (always preceded by a string)
      n = add_str(t, n, lstr, str_sub(pattern, i, s - 1))
      if str_find(patt, '${', 1, true) then
        error("patterns and ${vars} must be separated by '/'", 2)
      end
      n = n + 1 ; t[n] = patt ; lstr = nil
      i = ep + 1 ; sp, ep, patt = str_find(pattern, match_patt_elem, i)
    else -- variable (optionally preceded by a string)
      if i < s then
        local str = str_sub(pattern, i, s - 1)
        n, lstr = add_str(t, n, lstr, str)
      end
      local v = (env or config)[name]
      if not v then error('no such variable ${'..name..'}', 2) end
      -- if the var is a string containing LIST_SEPS, turn it into a table
      if type(v) == 'string' then
        local ss, e = str_find(v, LIST_SEPS_PATT)
        if ss then
          local tt, ii = {str_sub(v, 1, ss - 1)}
          repeat
            ii = e + 1 ; ss, e = str_find(v, LIST_SEPS_PATT, ii)
            tt[#tt + 1] = str_sub(v, ii, ss and ss - 1)
          until not ss
          v = tt
        end
      end
      if type(v) ~= 'table' then n, lstr = add_str(t, n, lstr, tostring(v))
      elseif #v > 1 then n = n + 1 ; t[n] = v ; lstr = nil
      elseif #v == 1 then n, lstr = add_str(t, n, lstr, tostring(v[1])) end
      i = ev + 1 ; sv, ev, name = str_find(pattern, match_var, i)
    end
  end
  if i < #pattern then n = add_str(t, n, lstr, str_sub(pattern, i)) end
  -- we may hook the following functions for debugging
  local _init, _stat = init, stat ; if enable_debug then
    _init = function(...)
      local a, b = init(...)
      if not b then print('glob: nil', a) end
      return a, b
    end
    local ic = 0
    _stat = function(path)
      if ic >= 99 then error('glob exceeded '..ic..' iterations') end
      ic = ic + 1 ; local r = stat(path) print('glob:', r, path) return r
    end
  end
  return cache[n](_init, _stat, abs, tbl_concat, t, unpack(t))
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
  is_abs = is_abs,
  is_dir = is_dir,
  is_file = is_file,
  is_root = is_root,
  join = join,
  make = make,
  mkdir = mkdir,
  match = match,
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

