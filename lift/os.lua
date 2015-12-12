------------------------------------------------------------------------------
-- Operating System utility functions and child process management
------------------------------------------------------------------------------

local assert = assert
local co_yield = coroutine.yield
local tbl_concat = table.concat

local diagnostics = require 'lift.diagnostics'
local async = require 'lift.async'
local async_get, async_resume = async._get, async._resume

local util = require 'lift.util'
local UNIX, WINDOWS = util._UNIX, util._WINDOWS

local uv = require 'lluv'
local uv_pipe, uv_spawn = uv.pipe, uv.spawn
local UV_CREATE_WRITABLE_PIPE = (uv.CREATE_PIPE + uv.WRITABLE_PIPE)
-- local UV_CREATE_READABLE_PIPE = (uv.CREATE_PIPE + uv.READABLE_PIPE)

------------------------------------------------------------------------------
-- Child Process (object)
------------------------------------------------------------------------------

-- custom diagnostic for child process and spawn related errors
diagnostics.levels.child_process_error = 'fatal'
diagnostics.styles.child_process_error =
  {prefix = 'error in child process:', fg = 'red'}

-- given a list of strings read from a stream, return a whole string
local function from_text_stream(buffer)
  local str = tbl_concat(buffer)
  return UNIX and str or str:gsub('\r\n', '\n') -- normalize newlines
end

------------------------------------------------------------------------------
-- Spawn a child process
------------------------------------------------------------------------------

local stdignore = {}

------------------------------------------------------------------------------
-- Shell commmand execution
------------------------------------------------------------------------------

local shell_program = (UNIX and '/bin/sh' or os.getenv'COMSPEC')

-- Returns the standard output of running `command` in a shell. If `command`
-- terminates with an error, returns nil plus a diagnostic object containing
-- the command's exit status and output.
-- Security: because sh() is vulnerable to shell injection, its use is strongly
-- discouraged in cases where `command` is constructed from external input.
local function sh(command)
  local this_future = async_get()
  local exit_err, exit_status, exit_signal
  local function on_exit(proc, err, status, signal)
    proc:close()
    exit_err = err
    exit_status = status
    exit_signal = signal
    async_resume(this_future)
  end
  local args = {UNIX and '-c' or '/C', command}
  local pout, perr = uv_pipe(), uv_pipe()
  local stdout = {stream = pout, flags = UV_CREATE_WRITABLE_PIPE}
  local stderr = {stream = perr, flags = UV_CREATE_WRITABLE_PIPE}
  local proc, pid = uv_spawn({file = shell_program, args = args,
                        stdio = {stdignore, stdout, stderr}}, on_exit)
  assert(proc, pid)
  pout:start_read(function(pipe, err, data)
    if err then return pipe:close() end
    stdout[#stdout+1] = data
  end)
  perr:start_read(function(pipe, err, data)
    if err then return pipe:close() end
    stderr[#stderr+1] = data
  end)
  co_yield()
  stdout, stderr = from_text_stream(stdout), from_text_stream(stderr)
  if exit_err then
    return nil, diagnostics.new(
      "child_process_error: spawn failed with error '${1}'", exit_err)
  elseif exit_status ~= 0 or exit_signal ~= 0 then
    local reason = (exit_signal == 0 and 'failed' or 'interrupted')
    return nil, diagnostics.new{'child_process_error: command ${reason} '..
      '(${exit_status}/${signal}): ${stderr}',
      reason = reason, exit_status = exit_status, signal = exit_signal,
      stdout = stdout, stderr = stderr}
  end
  return stdout, stderr
end

------------------------------------------------------------------------------
-- Module Initialization
------------------------------------------------------------------------------

return {
  UNIX = UNIX,
  WINDOWS = WINDOWS,
  sh = sh,
}
