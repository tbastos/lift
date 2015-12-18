------------------------------------------------------------------------------
-- Child process management and operating system utility functions
------------------------------------------------------------------------------

local assert, setmetatable = assert, setmetatable
local co_yield = coroutine.yield
local diagnostics = require 'lift.diagnostics'
local native_to_lf = require'lift.string'.native_to_lf
local async = require 'lift.async'
local async_get, async_resume = async._get, async._resume
local util = require 'lift.util'
local UNIX, WINDOWS = util._UNIX, util._WINDOWS
local uv = require 'luv'
local uv_new_pipe, uv_read_start = uv.new_pipe, uv.read_start
local uv_new_timer, uv_timer_start  = uv.new_timer, uv.timer_start
local uv_close, uv_process_kill, uv_spawn = uv.close, uv.process_kill, uv.spawn

------------------------------------------------------------------------------
-- ChildProcess objects and spawn()
------------------------------------------------------------------------------

-- custom diagnostic for child process related errors
diagnostics.levels.child_process_error = 'fatal'
diagnostics.styles.child_process_error =
  {prefix = 'error in child process:', fg = 'red'}

local ChildProcess = {}
ChildProcess.__index = ChildProcess

-- Sends a signal to the process. Defaults to SIGTERM (terminate process).
function ChildProcess:kill(signal)
  local h = self.handle
  if h then
    uv_process_kill(self.handle, signal or 'sigterm')
  else
    error('process:kill() called after process termination', 2)
  end
end

-- Registers a function to be called when the process terminates.
function ChildProcess:on_exit(cb)
  local t = self.on_exit_cb
  t[#t+1] = cb
end

function ChildProcess:wait(timeout)
  if not self.handle then return true end -- already exited
  local this_future = async_get()
  local status, signal, cb
  if timeout then
    local timer = uv_new_timer()
    cb = function(p, _status, _signal)
        if timer == nil then return false end -- ignore second call
        status, signal = _status or false, _signal or 'timed out'
        async_resume(this_future)
        uv_close(timer)
        timer = nil
      end
    uv_timer_start(timer, timeout, 0, cb)
  else
    cb = function(p, _status, _signal)
        status, signal = _status, _signal
        async_resume(this_future)
      end
  end
  self:on_exit(cb)
  co_yield()
  return status, signal
end

local spawn = diagnostics.trace(
  '[os] spawning process ${t}',
  function(p)
    local file = p.file
    if not file then error('you must specify a file to spawn()', 2) end
    p.args = p
    -- handle stdio options
    local si, so, se = p.stdin or 'pipe', p.stdout or 'pipe', p.stderr or 'pipe'
    if si == 'pipe' then si = uv_new_pipe(false)
    elseif si == 'ignore' then si = nil elseif si == 'inherit' then si = 0 end
    if so == 'pipe' then so = uv_new_pipe(false)
    elseif so == 'ignore' then so = nil elseif so == 'inherit' then so = 1 end
    if se == 'pipe' then se = uv_new_pipe(false)
    elseif se == 'ignore' then se = nil elseif se == 'inherit' then se = 2 end
    p.stdio = {si, so, se} -- TODO we could avoid using a table for stdio
    -- hide console windows by default on Windows
    if WINDOWS and p.hide == nil then p.hide = true end
    -- spawn and check for error
    local proc, pid = uv_spawn(file, p, function(status, signal)
        p.status = status
        p.signal = signal
        uv_close(assert(p.handle))
        p.handle = nil
        local cb_list = p.on_exit_cb
        for i = 1, #cb_list do
          cb_list[i](p, status, signal)
        end
      end)
    if not proc then
      return nil, diagnostics.new("child_process_error: spawn failed: ${1}", pid)
    end
    p.args, p.stdio = nil, nil
    p.pid = pid
    p.handle = proc
    p.on_exit_cb = {}
    return setmetatable(p, ChildProcess)
  end)

------------------------------------------------------------------------------
-- sh() facilitates the execution of shell commmands
------------------------------------------------------------------------------

local shell_program = (UNIX and '/bin/sh' or os.getenv'COMSPEC')

-- Returns the stdout and stderr of running `command` in the OS shell, or nil
-- plus a diagnostic object (with exit state and output) when `command` fails.
-- Line endings in stdout and stderr are normalized to LF.
-- Security Notice: never execute a command interpolated with external input
-- (such as a config string) as that leaves you vulnerable to shell injection.
local function sh(command)
  local this_future = async_get()
  local status, signal
  local function on_exit(_status, _signal)
    status = _status
    signal = _signal
    async_resume(this_future)
  end
  local stdout, stderr = uv_new_pipe(false), uv_new_pipe(false)
  local options = {UNIX and '-c' or '/C', command, -- args
    stdio = {nil, stdout, stderr}, hide = true}
  options.args = options
  local proc, pid = uv_spawn(shell_program, options, on_exit)
  if not proc then
    return nil, diagnostics.new("child_process_error: spawn failed: ${1}", pid)
  end
  local so, se = '', ''
  uv_read_start(stdout, function(err, data)
    if data then so = so..data end
  end)
  uv_read_start(stderr, function(err, data)
    if data then se = se..data end
  end)
  co_yield()
  uv_close(proc)
  so, se = native_to_lf(so), native_to_lf(se)
  if status ~= 0 or signal ~= 0 then
    local what = (signal == 0 and 'failed' or 'interrupted')
    return nil, diagnostics.new{'child_process_error: command ${what} '..
      '(${status}/${signal}): ${stderr}', what = what, status = status,
      signal = signal, stdout = so, stderr = se}
  end
  return so, se
end

------------------------------------------------------------------------------
-- Module Initialization
------------------------------------------------------------------------------

return {
  UNIX = UNIX,
  WINDOWS = WINDOWS,
  sh = sh,
  spawn = spawn,
}
