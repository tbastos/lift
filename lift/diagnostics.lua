------------------------------------------------------------------------------
-- Diagnostics and Error Handling
------------------------------------------------------------------------------
-- This is a unified module for error reporting and debug tracing. It
-- doesn't include a fully fledged logging system, but allows you to
-- integrate one through a diagnostics consumer. The focus here is
-- on an error handling system well suited to tools and compilers.

local rawget, type = rawget, type
local unpack = table.unpack or unpack -- LuaJIT compatibility
local clock = os.clock
local str_find, str_sub = string.find, string.sub
local dbg_getinfo, dbg_getupvalue = debug.getinfo, debug.getupvalue
local dbg_traceback = debug.traceback

local ls = require 'lift.string'
local ls_expand, ls_format, ls_capitalize = ls.expand, ls.format, ls.capitalize

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
-- Diagnostic (a specially-formatted message, plus arguments and decorators)
------------------------------------------------------------------------------

-- decorators in the hash part, arguments in the array part
local Diagnostic = {
  kind = 'error',
  level = 'error',
}

-- compute diag.message lazily
function Diagnostic:__index(k)
  if k == 'message' then
    local msg = ls_expand(rawget(self, 0) or 'no message', self)
    self.message = msg
    return msg
  end
  return Diagnostic[k]
end

-- returns whether a value is a diagnostic
local function is_a(t) return getmetatable(t) == Diagnostic end

-- creates a diagnostic from a message in the format "kind: message"
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

-- tostring(diagnostic) == diagnostic:format()
function Diagnostic:__tostring() return self:format() end

-- formats the diagnostic to a string
function Diagnostic:format()
  local style = styles[self.kind] or styles[self.level]
  local loc, str, prefix = self.location, '', style.prefix
  if loc then str = loc.file..':'..loc.line..': '
  else prefix = ls_capitalize(prefix) end
  return str..prefix..' '..self.message
end

-- we report to a diagnostic consumer and keep track of the last error
local consumer, last_error
local function set_consumer(c)
  local previous = consumer
  consumer, last_error = c, nil
  return previous
end

function Diagnostic:report()
  assert(consumer, 'undefined diagnostics consumer')
  local level = self.level
  if level == 'ignored' then return
  elseif level == 'error' then last_error = self
  elseif level == 'fatal' then error(self) end
  consumer(self) -- notify consumer (if non-fatal)
end

-- shortcut to new(...):report() for diagnostics without decorators
local function report(...) new(...):report() end

-- raises the most recent error-level diagnostic, if we got one
local function fail_if_error()
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
function Diagnostic:function_location(level)
  local info = dbg_getinfo(level, 'Sl')
  self.location = {file = info.short_src, line = info.currentline}
  return self
end

------------------------------------------------------------------------------
-- Decorator: 'lua_stb' (prints a Lua stack traceback)
------------------------------------------------------------------------------

-- default level is 1 (the function calling lua_traceback)
function Diagnostic:lua_traceback(level)
  self.lua_stb = dbg_traceback(nil, (level or 1) + 1)
  return self
end

------------------------------------------------------------------------------
-- Verifier (a consumer that accumulates diagnostics for testing)
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
-- Reporter (a consumer that prints diagnostics to stderr)
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

function Reporter:__call(diagnostic)
  self:report(diagnostic)
end

function Reporter:report(d)
  local style = styles[d.kind] or styles[d.level]
  local loc, prefix = d.location, style.prefix
  if loc then -- source file location
    stderr:write(ESC'bold;white', loc.file, ':', loc.line, ':')
    if loc.column then stderr:write(loc.column, ': ') end
  else
    prefix = ls_capitalize(prefix)
  end
  stderr:write(color.from_style(style), prefix, ESC'clear',
    style.sep or ' ', d.message, ESC'clear', '\n')
  if d.lua_stb then -- Lua stack traceback
    stderr:write(d.lua_stb, '\n')
  end
  if d.activity_trace then -- activity trace created by trace()
    stderr:write('\n', ESC'yellow', 'Trace:', ESC'clear', '\n')
    for i, msg in ipairs(d.activity_trace) do
      stderr:write((' '):rep(i * 2), msg, '\n')
    end
    stderr:write('\n')
  end
end

------------------------------------------------------------------------------
-- Call tracing and custom pcall() with better error reporting
------------------------------------------------------------------------------

-- tracing is disabled by default
local tracing, stack = false, {}
local function set_tracing(v) tracing = v end

-- expand_up(msg, f) expands vars using the upvalues of a function
local function get_upvalue(f, name)
  for i = 1, 9 do -- limited to the first 9 upvalues
    local n, v = dbg_getupvalue(f, i)
    if not n then break
    elseif n == name then return ls_format(v) end
  end
end
local function expand_up(message, f)
  return ls_expand(message, f, get_upvalue)
end

-- Traces a call to f(). If tracing is enabled, msg is expanded with f's
-- upvalues and printed to stderr. Also, if diagnostics.pcall() catches
-- an error, it prints msg in the activity trace.
local function trace(msg, f, ...)
  local n, t0 = #stack
  stack[n + 1] = msg
  stack[n + 2] = f
  if tracing then
    if n == 0 then t0 = clock() end -- measure the time of 1st-level calls
    stderr:write(ESC'clear;blue', (' '):rep(n), expand_up(msg, f), ESC'clear', '\n')
  end
  f(...)
  assert(#stack == n + 2, 'unbalanced activity stack')
  stack[n + 2] = nil
  stack[n + 1] = nil
  if t0 then -- we're timing this call
    local tmsg = ('%.2f'):format(clock() - t0)
    stderr:write(ESC'cyan', (' '):rep(n + 2), 'Elapsed time ', tmsg, 's',
      ESC'clear', '\n')
  end
end

-- custom diagnostic for Lua errors
levels.lua_error = 'fatal'
styles.lua_error = {prefix = 'Lua error!', sep = '\n', fg = 'red'}

-- custom error handler for xpcall
local function error_handler(diag)
  -- if this is a regular Lua error, convert it to a diagnostic
  if not is_a(diag) then
    diag = new("lua_error: ${1}", diag):lua_traceback(3)
  end
  -- add the activity stack built by trace()
  if #stack > 0 then
    local t = {}
    for i = 1, #stack, 2 do
      t[#t + 1] = expand_up(stack[i], stack[i + 1])
    end
    diag.activity_trace = t
    stack = {}
  end
  return diag
end

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
-- capture(f) calls f and captures stdout and diagnostics (for testing)
------------------------------------------------------------------------------

local capturing = false
local function capture(f)
  assert(not capturing, "diagnostics.capture() cannot be called recursively")
  capturing = true

  -- save original output stream and diagnostics consumer
  local o_ostream, o_consumer = io.output(), consumer

  -- capture output and diagnostics
  local fout = assert(io.tmpfile())
  io.output(fout)
  local verifier = Verifier.set_new()
  local ok = pcall(f)
  fout:seek('set')
  local output = fout:read('*a')

  -- restore original output stream and diagnostics consumer
  set_consumer(o_consumer)
  io.output(o_ostream)
  fout:close()

  capturing = false
  return ok, output, verifier
end

------------------------------------------------------------------------------
-- Utility functions to help debug programs
------------------------------------------------------------------------------

-- Pretty prints a value to stdout.
local function pp(value, label)
  if label then
    io.write(label, ' = ', ls_format(value), '\n')
  else
    io.write(ls_format(value), '\n')
  end
end

------------------------------------------------------------------------------
-- Module Table
------------------------------------------------------------------------------

return {
  capture = capture,
  fail_if_error = fail_if_error,
  is_a = is_a,
  levels = levels,
  new = new,
  pcall = pcall,
  pp = pp,
  report = report, Reporter = Reporter,
  set_consumer = set_consumer,
  set_stderr = set_stderr,
  set_tracing = set_tracing,
  styles = styles,
  trace = trace,
  Verifier = Verifier,
  wrap = wrap,
}
