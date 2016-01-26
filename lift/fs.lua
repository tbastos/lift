------------------------------------------------------------------------------
-- File system operations
------------------------------------------------------------------------------

local assert, tostring, type = assert, tostring, type
local tbl_concat = table.concat
local str_find, str_match = string.find, string.match
local str_gsub, str_sub = string.gsub, string.sub
local co_wrap, co_yield = coroutine.wrap, coroutine.yield

local stream = require 'lift.stream'
local diagnostics = require 'lift.diagnostics'

local lp = require 'lift.path'
local from_slash, to_slash = lp.from_slash, lp.to_slash
local clean, dir, is_abs = lp.clean, lp.dir, lp.is_abs

local ls = require 'lift.string'
local from_glob, str_to_list = ls.from_glob, ls.to_list

local uv = require 'luv'
local uv_access = uv.fs_access
local uv_chdir = uv.chdir
local uv_chmod = uv.fs_chmod
local uv_cwd = uv.cwd
local uv_fclose = uv.fs_close
local uv_fopen = uv.fs_open
local uv_fread = uv.fs_read
local uv_fwrite = uv.fs_write
local uv_link = uv.fs_link
local uv_mkdir = uv.fs_mkdir
local uv_readlink = uv.fs_readlink
local uv_realpath = uv.fs_realpath
local uv_rename = uv.fs_rename
local uv_rmdir = uv.fs_rmdir
local uv_scandir = uv.fs_scandir
local uv_scandir_next = uv.fs_scandir_next
local uv_stat = uv.fs_stat
local uv_symlink = uv.fs_symlink
local uv_unlink = uv.fs_unlink
local uv_utime = uv.fs_utime

------------------------------------------------------------------------------
-- Basic operations
------------------------------------------------------------------------------

-- Tests access permissions to the file specified by `path`. The `mode` can be
-- omitted to test for file existence, or it can be a combination of the
-- strings 'r', 'w' and 'x', or an integer (the sum of 4(r), 2(w) and 1(x)).
-- Returns true if permission is granted, or false otherwise.
local function access(path, mode)
  return uv_access(from_slash(path), mode or 0)
end

-- Changes the current working directory.
local function chdir(path) return uv_chdir(from_slash(path)) end

-- Sets the permission bits of the file specified by `path` to `mode` (integer).
local function chmod(path, mode) return uv_chmod(from_slash(path), mode) end

-- Returns the current working directory.
local function cwd() return to_slash(uv_cwd()) end

-- Creates a new name for a file.
local function link(path, new_path)
  return uv_link(from_slash(path), from_slash(new_path)) -- 493 = 0755
end

-- Creates the directory `path` with the permissions specified by `mode` and
-- restricted by the umask of the calling process. By default, mode = 0755.
local function mkdir(path, mode)
  return uv_mkdir(from_slash(path), mode or 493) -- 493 = 0755
end

-- Returns the value of a symbolic link.
local function readlink(path) return to_slash(uv_readlink(from_slash(path))) end

-- Expands symbolic links and returns the canonicalized absolute name of `path`.
local function realpath(path) return to_slash(uv_realpath(from_slash(path))) end

-- Causes the link named `from` to be renamed as `to`.
local function rename(from, to) return uv_rename(from_slash(from), from_slash(to)) end

-- Deletes a directory, which must be empty.
local function rmdir(path) return uv_rmdir(from_slash(path)) end

-- Returns an iterator function/object so that the construction
--   for name in fs.scandir(path) do ... end
-- will iterate over the directory entries in `path`.
local function _scandir_next(dir_req)
  local t = uv_scandir_next(dir_req) -- TODO this shouldn't return a table
  if not t then return end
  return t.name, t.type
end
local function scandir(path) return _scandir_next, uv_scandir(from_slash(path)) end

-- Returns a table containing information about the file pointed to by `path`.
-- Available fields: dev, mode, nlink, uid, gid, rdev, ino, size, blksize,
--   blocks, flags, gen, atime, mtime, ctime, birthtime and type.
-- Type is one of: file, directory, link, fifo, socket, char, block.
local function stat(path) return uv_stat(from_slash(path)) end

-- Returns true if path exists and is a file.
local function is_file(path)
  local t = stat(path)
  return t and t.type == 'file' or false
end

-- Returns true if path exists and is a directory.
local function is_dir(path)
  local t = stat(path)
  return t and t.type == 'directory' or false
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

-- Creates a symbolic link `new_path` pointing to `path`.
local function symlink(path, new_path)
  return uv_symlink(from_slash(path), from_slash(new_path))
end

-- Deletes a name and possibly the file it refers to.
local function unlink(path)
  return uv_unlink(from_slash(path))
end

-- Sets the last access and modification times of the file specified by `path`.
local function utime(path, atime, mtime)
  return uv_utime(from_slash(path), atime, mtime)
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

local ANY_DELIMITER = '['..ls.DELIMITERS..']'

-- Creates a path pattern table from a `glob` string.
-- A pattern table is a list where each elem is either a string or a list.
local function glob_parse(glob, vars, get_var)
  vars, get_var = vars or (require 'lift.config'), get_var or index_table
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
      v = str_to_list(v)
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
    if not et then et = stat(path..'/'..name).type end
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
  local base_dir = is_abs(pattern) and '' or (cwd()..'/')
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
-- File I/O Streams
------------------------------------------------------------------------------

local default_permissions = tonumber('664', 8)

local function push_error(s, err)
  s:push(nil, diagnostics.new{'error: ${uv_err}', stream = s, uv_err = err})
end

local function read_from(path, bufsize)
  bufsize = bufsize or 16384 -- read in 16KB blocks by default
  local reading = false
  local file, s, read_more
  local function read_cb(err, chunk)
    if err then return push_error(s, err) end
    if chunk == '' then
      uv_fclose(file, function(err) -- luacheck: ignore
        if err then return push_error(s, err) end
        s:push()
      end)
    else
      if s:push(chunk) then
        read_more()
      else
        reading = false
      end
    end
  end
  read_more = function()
    uv_fread(file, bufsize, -1, read_cb)
  end
  local function reader(_stream)
    if reading then return end
    reading = true
    if file then
      read_more()
    else
      s = _stream
      uv_fopen(path, 'r', default_permissions, function(err, fd)
        if err then return push_error(s, err) end
        file = fd
        read_more()
      end)
    end
  end
  return stream.new_readable(reader, 'file '..path)
end

local function write_to(path)
  local file
  local function writer(s, data, err, callback)
    if err then return callback(err) end
    if data then
      if file then
        uv_fwrite(file, data, -1, callback)
      else
        uv_fopen(path, 'w', default_permissions, function(e, fd)
          if e then return callback(e) end
          file = fd
          uv_fwrite(file, data, -1, callback)
        end)
      end
    else
      assert(file)
      uv_fclose(file, callback)
      file = nil
    end
  end
  local function write_many(s, chunks, callback)
    assert(file)
    uv_fwrite(file, chunks, -1, callback)
  end
  return stream.new_writable(writer, write_many, 'file '..path)
end

------------------------------------------------------------------------------
-- Module Table
------------------------------------------------------------------------------

return {
  access = access,
  chdir = chdir,
  chmod = chmod,
  cwd = cwd,
  glob = glob,
  glob_parse = glob_parse,      -- exported for testing
  glob_product = glob_product,  -- exported for testing
  is_dir = is_dir,
  is_file = is_file,
  link = link,
  match = match,                -- exported for testing
  mkdir = mkdir,
  mkdir_all = mkdir_all,
  read_from = read_from,
  readlink = readlink,
  realpath = realpath,
  rename = rename,
  rmdir = rmdir,
  scandir = scandir,
  symlink = symlink,
  unlink = unlink,
  utime = utime,
  write_to = write_to,
}
