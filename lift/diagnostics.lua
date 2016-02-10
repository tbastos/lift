------------------------------------------------------------------------------
-- Diagnostics reporting, error handling and debug tracing
------------------------------------------------------------------------------
-- This is a unified module for error handling, diagnostics reporting and debug
-- tracing. It does NOT provide a general-purpose logging system, but allows
-- you to integrate with one via diagnostics consumers. The central abstraction
-- is the diagnostic object, which can be used as an error object in Lua.
-- Lower-level functions may return nil plus a diagnostic object to signal an
-- error, while higher-level functions decorate the object with contextual
-- information and raise them as errors. Diagnostics that are not raised as
-- errors can be reported as warnings, remarks, or custom kinds of diagnostics.

local assert, rawget, type, xpcall = assert, rawget, type, xpcall
local getmetatable, setmetatable = getmetatable, setmetatable
local unpack = table.unpack or unpack -- LuaJIT compatibility
local clock = os.clock
local str_find, str_gmatch, str_match = string.find, string.gmatch, string.match
local str_rep, str_sub = string.rep, string.sub
local dbg_getinfo, dbg_getlocal = debug.getinfo, debug.getlocal
local dbg_traceback = debug.traceback

local to_slash = require'lift.path'.to_slash

local ls = require 'lift.string'
local ls_expand, ls_capitalize = ls.expand, ls.capitalize

local inspect = require'lift.util'.inspect

local color = require 'lift.color'
local ESC = color.ESC

-- allow stderr to be redirected
local stderr = io.stderr
local function set_stderr(fd) stderr = fd end

------------------------------------------------------------------------------
-- Diagnostic Levels (ignored, remark, warning, error, fatal)
------------------------------------------------------------------------------

-- Map of diagnostic kind to severity level; 'error' must always map
-- to either 'error' or 'fatal', and 'fatal' cannot be changed.
local levels = {
  ignored = 'ignored', -- never reported
  remark  = 'remark',  -- optionally reported
  warning = 'warning', -- always reported (program doesn't halt)
  error   = 'error',   -- program halts at the next checkpoint
  fatal   = 'fatal',   -- program halts immediately
}

------------------------------------------------------------------------------
-- Diagnostic Styles (hints on how to render a diagnostic)
------------------------------------------------------------------------------

local styles = {
  remark  = { prefix = '--', fg = 'green' },
  warning = { prefix = 'warning:', fg = 'magenta' },
  error   = { prefix = 'error:', fg = 'red' },
  fatal   = { prefix = 'error:', fg = 'red', bold = true },
}

------------------------------------------------------------------------------
-- Diagnostic (message with sequential arguments and properties/decorators)
------------------------------------------------------------------------------

-- objects keep decorators in the hash part, arguments in the array part
local Diagnostic = {
  kind = 'error',
  level = 'error',
}

-- expands vars in a diagnostic message
local function get_var(d, k)
  local v = d[k]
  if type(v) == 'function' then
    v = v(d) -- expand functions by calling them with the diagnostic object
  end
  return v
end

-- compute diagnostic.message lazily
function Diagnostic:__index(k)
  if k == 'message' then
    local msg = ls_expand(rawget(self, 0) or 'no message', self, get_var)
    self.message = msg
    return msg
  end
  return Diagnostic[k]
end

-- Returns whether a value is a diagnostic.
local function is_a(value)
  return getmetatable(value) == Diagnostic
end

-- Creates a diagnostic from a message in the format "kind: my message".
local function new(t, ...)
  local m -- message
  if type(t) == 'table' then
    m = t[1] ; for i = 1, #t do t[i] = t[i + 1] end -- shift elements left
  else
    m, t = t, {...}
  end
  assert(type(m) == 'string', "first arg must be a message")
  local sep = str_find(m, ': ', nil, true)
  if not sep then error("malformed diagnostic message '"..m.."'", 2) end
  local kind, raw_message = str_sub(m, 1, sep - 1), str_sub(m, sep + 2)
  local level = levels[kind]
  if not level then error("unknown diagnostic kind '"..kind.."'", 2) end
  t.level, t.kind, t[0] = level, kind, raw_message
  return setmetatable(t, Diagnostic)
end

-- tostring(diagnostic) == diagnostic:inspect() (allows polymorphism)
function Diagnostic:__tostring() return self:inspect() end

-- Returns a concise string representation of the diagnostic.
local function inspect_diagnostic(d)
  local loc, str = d.location, ''
  if loc then str = loc.file..':'..loc.line..': ' end
  return str..d.kind..': '..d.message
end
Diagnostic.inspect = inspect_diagnostic

-- report to a diagnostic consumer and keep track of the last error
local consumer, last_error
local function set_consumer(c)
  local previous = consumer
  consumer, last_error = c, nil
  return previous
end

function Diagnostic:report()
  local level = self.level
  if level == 'ignored' then return
  elseif level == 'error' then last_error = self
  elseif level == 'fatal' then error(self) end
  assert(consumer, 'undefined diagnostics consumer')
  consumer(self) -- notify consumer (if non-fatal)
end

-- Short for new(...):report()
local function report(...) new(...):report() end

-- Creates and raises a diagnostic object as an error with a location.
-- The first argument is a table describing the diagnostic, as can be
-- passed to new(). The second (and optional) argument indicates the
-- stack level where the error occurred, with the same semantics as
-- Lua's standard error() function.
local function raise(diagnostic_descr_table, level)
  local d = new(diagnostic_descr_table)
  if level ~= 0 then d:set_location((level or 1) + 1) end
  error(d)
end

-- Raises the most recent error-level diagnostic
local function check_error()
  if last_error then error(last_error) end
end

------------------------------------------------------------------------------
-- Decorator 'location' (indicates a position in a source file)
------------------------------------------------------------------------------

local function get_line(source, pos)
  local lend, lnum, lstart = 0, 0
  repeat
    lstart = lend + 1
    lnum = lnum + 1
    lend = str_find(source, '\n', lstart, true)
  until not lend or lend >= pos
  return str_sub(source, lstart, lend and lend - 1), lnum, pos - lstart + 1
end

-- sets location based on filename, contents (string) and position (in string)
function Diagnostic:source_location(file, contents, pos)
  local code, line, column = get_line(contents, pos)
  self.location = {file = file, line = line, column = column, code = code}
  return self
end

-- sets location based on debug.getinfo (stack level or function)
function Diagnostic:set_location(level_or_f)
  local info, line
  if type(level_or_f) == 'number' then
    info = dbg_getinfo(level_or_f + 1, 'Sl')
    line = info.currentline
  else -- function
    info = dbg_getinfo(level_or_f, 'S')
    line = info.linedefined
  end
  local file = to_slash(info.short_src)
  self.location = {file = file, line = line}
  return self
end

------------------------------------------------------------------------------
-- Decorator: 'stb' (a Lua stack traceback)
------------------------------------------------------------------------------

-- default level is 1 (the function calling traceback)
function Diagnostic:traceback(level)
  self.stb = dbg_traceback(nil, level + 1)
  return self
end

------------------------------------------------------------------------------
-- Nested Diagnostics (aggregates multiple diagnostic objects into one)
------------------------------------------------------------------------------

local function inspect_nested(d)
  local s, nested = inspect_diagnostic(d), d.nested
  for i = 1, #nested do
    s = s..'\n  ('..i..') '..inspect_diagnostic(nested[i])
  end
  return s
end

-- Creates a diagnostic based on a message and a list of nested diagnostics.
local function aggregate(message, elements)
  local n = #elements
  return new{message, nested = elements, n = n, s = (n > 1 and 's' or ''),
    inspect = inspect_nested}
end

------------------------------------------------------------------------------
-- Verifier (consumer that accumulates diagnostics for testing)
------------------------------------------------------------------------------

local Verifier = {}
Verifier.__index = Verifier

function Verifier.new()
  return setmetatable({}, Verifier)
end

function Verifier.set_new()
  local verifier = Verifier.new()
  set_consumer(verifier)
  return verifier
end

function Verifier:__call(diagnostic)
  self[#self + 1] = diagnostic
end

-- raises an error if str_list does not match the verifier's diag list
function Verifier:verify(str_list)
  -- lists must have the same length
  if #self ~= #str_list then
    error('expected '..#str_list..' but got '..#self..' diagnostics', 2)
  end
  for i = 1, #self do
    local expected = str_list[i]
    local actual = tostring(self[i])
    if not str_find(actual, expected, 1, true) then
      error('mismatch at diagnostic #'..i..'\nActual: '..actual..
        '\nExpected: '..expected, 2)
    end
  end
end

------------------------------------------------------------------------------
-- Reporter (consumer that prints diagnostics to stderr)
------------------------------------------------------------------------------

local Reporter = {}
Reporter.__index = Reporter

function Reporter.new()
  return setmetatable({}, Reporter)
end

function Reporter.set_new()
  local reporter = Reporter.new()
  set_consumer(reporter)
  return reporter
end

local function print_report(d, id, level)
  local indent = str_rep('  ', level + 1)
  local style = styles[d.kind] or styles[d.level]
  local prefix = style.prefix
  local future = d.future
  local task = future and future.task
  local location = d.location
  -- Identifier (for nested diagnostics)
  if id ~= '' then
    stderr:write(str_rep(' ', level * 2 - 1), id, ') ')
  end
  -- Thread of origin (if not a task)
  if future and not task then
    stderr:write('In ', ESC'green', tostring(future), ESC'clear', ':\n', indent)
  end
  -- Location
  if location then
    local col = location.column
    stderr:write(ESC'bold', location.file, ':',
      location.line, col and ':'..col or '', ': ', ESC'clear')
  else
    prefix = ls_capitalize(prefix)
  end
  -- Task
  if task then
    stderr:write('in task ', ESC'green', tostring(task), ESC'clear', '\n', indent)
    prefix = ls_capitalize(prefix)
  end
  -- Kind (prefix) and Message
  stderr:write(color.from_style(style), prefix, ' ', ESC'clear', d.message, '\n')
  -- Stack traceback
  local stb = d.stb
  if stb then
    stderr:write(indent, ESC'yellow', 'Stack traceback:', ESC'clear', '\n')
    for line in str_gmatch(stb, '\t([^\t]+)') do
      stderr:write(indent, '  ', line)
    end
    stderr:write('\n')
  end
  -- Nested diagnostics
  local nested = d.nested
  if nested then
    if id ~= '' then id = id..'.' end
    for i, nd in ipairs(nested) do
      stderr:write('\n')
      print_report(nd, id..i, level + 1)
    end
  end
end

function Reporter:__call(diagnostic)
  print_report(diagnostic, '', 0)
end

------------------------------------------------------------------------------
-- Tracing (near zero overhead; concise pre- and post-call messages; timing)
------------------------------------------------------------------------------

-- master switch
local tracing = ((os.getenv'TRACING' or os.getenv'LIFT_TRACING') ~= nil)
local tracing_switch = {} -- list of closures that can switch tracing on/off
local function set_tracing(v)
  for i = 1, #tracing_switch do
    tracing_switch[i](v)
  end
  local original = tracing
  tracing = v
  return original
end

-- helpers to expand trace messages
local nil_arg = setmetatable({}, {__tostring = function() return '<nil>' end})
local function expand_arg(t, name)
  local v = t[name]
  return v and inspect(v, 60)
end
local function expand_trace(msg, args)
  return ls_expand(msg, args, expand_arg)
end

-- Returns a function that calls f and optionally prints an execution trace.
-- When tracing is off, calling f costs only an indirection (function call).
-- When tracing is on, the messages 'pre' and 'post' are expanded with f's
-- arguments and printed before and after the call, respectively, to stderr.
-- The duration of the call is appended to the post message. The post message
-- can be omitted, in which case timing is disabled. Tracing is not protected,
-- so if f raises an error, the post message is not printed.
local function trace(pre, post, f)
  -- sanitize arguments
  assert(type(pre) == 'string', 'argument #1 to trace() must be a message string')
  if type(post) == 'function' then post, f = nil, post end -- no post message
  assert(post == nil or type(post) == 'string',
    'argument #2 to trace() must be a message string or a function')
  assert(type(f) == 'function', "last argument to trace() must be a function")
  -- tracing wrapper function
  local function trace_f(...)
    local args = {...} -- f's arguments indexable by name or sequentially
    for i = 1, 9 do -- assumes a limit of 9 parameters
      local name = dbg_getlocal(f, i)
      if not name then break end
      args[name] = args[i] or nil_arg
    end
    stderr:write(ESC'blue', expand_trace(pre, args), ESC'clear', '\n')
    if not post then return f(...) end -- optimization
    -- time the call and print post message
    local t0 = clock()
    local res = {f(...)}
    local time = (' [%.2fs]'):format(clock() - t0)
    post = expand_trace(post, args)
    stderr:write(ESC'blue', post, ESC'cyan', time, ESC'clear', '\n')
    return unpack(res)
  end
  local call_f -- points to either f or trace_f
  local function switch_tracing(v)
    call_f = v and trace_f or f
  end
  tracing_switch[#tracing_switch+1] = switch_tracing
  switch_tracing(tracing)
  return function(...) return call_f(...) end
end

------------------------------------------------------------------------------
-- Custom pcall() that turns all errors into diagnostic objects
------------------------------------------------------------------------------

-- custom diagnostic for Lua runtime errors
levels.lua_error = 'fatal'
styles.lua_error = {prefix = 'Lua error:', fg = 'red'}

-- error handler for pcall (turns any error into a diagnostic object)
local function to_diagnostic(err, level)
  if is_a(err) then return err end
  local d = new("lua_error: ${1}", err):set_location(level):traceback(level)
  if type(err) == 'string' then -- try to erase 'file/path:ln: ' from err
    local file, line, e = str_match(err, '^(..[^:]+):([^:]+): ()')
    file = file and to_slash(file) -- normalize paths
    local loc = d.location
    if file == loc.file and tonumber(line) == loc.line then
      d[1] = str_sub(err, e) -- remove redundant information
    end
  end
  return d
end
local function error_handler(err) return to_diagnostic(err, 3) end
-- workaround busted messing with diagnostic objects in tests...
if package.loaded.busted then
  error_handler = function(err)
    if type(err) == 'table' then
      -- retrieve the diagnostic object from within busted's error object...
      if not is_a(err) and err.message then err = err.message end
    end
    return to_diagnostic(err, 3)
  end
end

-- A pcall that turns all errors into diagnostic objects.
-- Regular errors are always decorated with a stack traceback.
local function pcall(f, ...)
  return xpcall(f, error_handler, ...)
end

------------------------------------------------------------------------------
-- wrap(f) calls f and automatically reports errors and diagnostics
-- This is meant to be used only once, to wrap the whole program.
------------------------------------------------------------------------------

local function wrap(f)
  local t0 = clock()
  Reporter.set_new()
  local ok, diag = pcall(f)
  if not ok then
    if diag.level == 'fatal' then
      consumer(diag) -- notify fatal errors after they're caught
    end
    if diag.kind == 'cli_error' and diag.command then
      -- print help if the error was a cli usage error
      stderr:write(unpack(diag.command:get_help()))
      stderr:write('\n')
    end
  end
  if tracing then
    local dt, mem = (clock() - t0), collectgarbage 'count'
    local fmt = 'time %.2fs, memory %iK'
    if mem > 1024 then
      mem = mem / 1024
      fmt = 'time %.2fs, memory %.2fM'
    end
    stderr:write(ESC'cyan', 'Total ', fmt:format(dt, mem), ESC'clear', '\n' )
  end
  return ok, diag
end

------------------------------------------------------------------------------
-- Module Table
------------------------------------------------------------------------------

return {
  aggregate = aggregate,
  check_error = check_error,
  is_a = is_a,
  levels = levels,
  new = new,
  pcall = pcall,
  raise = raise,
  report = report, Reporter = Reporter,
  set_consumer = set_consumer,
  set_stderr = set_stderr,
  set_tracing = set_tracing,
  styles = styles,
  trace = trace,
  Verifier = Verifier,
  wrap = wrap,
}
