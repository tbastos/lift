------------------------------------------------------------------------------
-- File system operations
------------------------------------------------------------------------------
-- For now operations run synchronously, but will run async in the future.

local tostring, type = tostring, type
local tbl_concat = table.concat
local str_find, str_match = string.find, string.match
local str_gsub, str_sub = string.gsub, string.sub
local co_wrap, co_yield = coroutine.wrap, coroutine.yield

local config = require 'lift.config'
local lp = require 'lift.path'
local from_slash, to_slash = lp.from_slash, lp.to_slash
local clean, dir, is_abs = lp.clean, lp.dir, lp.is_abs

local ls = require 'lift.string'
local from_glob, split_string = ls.from_glob, ls.split

local uv = require 'luv'
local uv_chdir, uv_cwd = uv.chdir, uv.cwd
local uv_access, uv_stat = uv.fs_access, uv.fs_stat
local uv_mkdir, uv_rmdir = uv.fs_mkdir, uv.fs_rmdir
local uv_scandir, uv_scandir_next = uv.fs_scandir, uv.fs_scandir_next

------------------------------------------------------------------------------
-- Basic libuv wrappers
------------------------------------------------------------------------------

local function cwd() return to_slash(uv_cwd()) end
local function chdir(path) return uv_chdir(from_slash(path)) end
local function mkdir(path) return uv_mkdir(from_slash(path), 493) end -- 493 = 0755
local function rmdir(path) return uv_rmdir(from_slash(path)) end
local function access(path, mode) return uv_access(from_slash(path), mode) end
local function stat(path) return uv_stat(from_slash(path)) end

local function _scandir_next(dir_req)
  local t = uv_scandir_next(dir_req) -- FIXME shouldn't use tables here
  if not t then return end
  return t.name, t.type
end
local function scandir(path) return _scandir_next, uv_scandir(from_slash(path)) end

------------------------------------------------------------------------------
-- Extra Functions
------------------------------------------------------------------------------

-- Returns true if path exists and is a directory.
local function is_dir(path)
  local t = stat(path)
  return t and t.type == 'directory' or false
end

-- Returns true if path exists and is a file.
local function is_file(path)
  local t = stat(path)
  return t and t.type == 'file' or false
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
-- Globbing with shell-style patterns and n-fold ${variable} expansions
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

local ANY_DELIMITER = '['..ls.delimiters..']'

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
    if type(v) == 'string' and str_find(v, ANY_DELIMITER) then
      local list, li = {}, 0
      for str in split_string(v) do li = li + 1 ; list[li] = str end
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
-- The main purpose of this function is for writing tests for glob().
local function match_alternative(pattern, path)
  pattern = (str_gsub(from_glob(pattern), '%[^/]%*%[^/]%*/', '.*/')) -- handle **/
  return str_match(path, '^'..pattern..'$') ~= nil
end
local function match(path, glob, vars, get_var)
  local pt = glob_parse(glob, vars, get_var)
  return glob_product(pt, match_alternative, path) or false
end

-- visits all subdirs of path calling f on them
local function glob_starstar(f, path, ...)
  f(path, ...)
  for name, et in scandir(path) do
    if et == 'directory' and not str_find(name, '^%.') then -- ignore dotdirs
      local subdir = path..'/'..name
      glob_starstar(f, subdir, ...)
    end
  end
end

-- processes the glob pattern recursively while visiting matches
local function glob_recurse(path, pattern, init, len)
  -- find the next path segment containing a pattern
  local s, e, patt = str_find(pattern, '([^/]*[[*?][^/]*)', init)
  path = path..str_sub(pattern, init, s and s - 1) -- expand path to just before patt
  if not s then
    -- no more patterns, check if we have read access to the path...
    if access(path, 4) then co_yield(path) end
    return
  end
  -- scan files in current path
  local next_entry, dir_req = scandir(path)
  if not dir_req then return end -- not a dir, give up this path
  e = e + 1
  if patt == '**' then -- starstar: match any number of subdir
    if e >= len then error("expected a name or pattern after wildcard '**'", 0) end
    path = str_sub(path, 1, -2) -- remove trailing slash
    return glob_starstar(glob_recurse, path, pattern, e, len)
  end
  -- ignore dot files unless patt begins with a dot (ex: $HOME/.*/file)
  local ignore_dot = (str_sub(patt, 1, 1) ~= '.')
  patt = (ignore_dot and '^(%.?)' or '^')..from_glob(patt)..'$'
  while true do
    local name = next_entry(dir_req)
    if not name then break end
    local matched, _, dot = str_find(name, patt)
    if matched and dot ~= '.' then
      if e < len then -- pattern continues
        glob_recurse(path..name, pattern, e, len)
      else -- pattern ends here, and this is a match
        co_yield(path..name)
      end
    end
  end
end

-- called for all combinations of vars, with a complete pattern string
local function glob_alternative(pattern)
  local base_dir = is_abs(pattern) and '' or ((config.cd or cwd())..'/')
  glob_recurse(base_dir, pattern, 1, #pattern)
end

-- Finds all pathnames that match the glob pattern. Returns an iterator
-- that produces an absolute path (or nil) each time it's called.
local function glob(pattern, vars, get_var)
  local pt = glob_parse(pattern, vars, get_var)
  return co_wrap(function()
    glob_product(pt, glob_alternative)
  end)
end

------------------------------------------------------------------------------
-- Module Table
------------------------------------------------------------------------------

return {
  access = access,
  chdir = chdir,
  cwd = cwd,
  glob = glob,
  glob_parse = glob_parse,      -- exported for testing
  glob_product = glob_product,  -- exported for testing
  is_dir = is_dir,
  is_file = is_file,
  match = match,                -- exported for testing
  mkdir = mkdir,
  mkdir_all = mkdir_all,
  rmdir = rmdir,
  scandir = scandir,
}
