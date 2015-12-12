------------------------------------------------------------------------------
-- Operating System utility functions and child process management
------------------------------------------------------------------------------

local co_yield = coroutine.yield
local tbl_concat = table.concat

local diagnostics = require 'lift.diagnostics'
local async = require 'lift.async'
local async_get, async_resume = async._get, async._resume

local util = require 'lift.util'
local UNIX, WINDOWS = util._UNIX, util._WINDOWS

local uv = require 'luv'
local uv_new_pipe, uv_spawn, uv_close = uv.new_pipe, uv.spawn, uv.close
local uv_read_start = uv.read_start

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

------------------------------------------------------------------------------
-- Shell commmand execution
------------------------------------------------------------------------------

local shell_program = (UNIX and '/bin/sh' or os.getenv'COMSPEC')

-- Returns the output of running `command` in a shell. If `command` terminates
-- with an error, returns nil plus a diagnostic object containing the command's
-- exit state and output (both stdout and stderr).
-- Security: because sh() is vulnerable to shell injection, its use is strongly
-- discouraged in cases where `command` is constructed from external input.
local function sh(command)
  local this_future = async_get()
  local exit_status, exit_signal
  local function on_exit(status, signal)
    exit_status = status
    exit_signal = signal
    async_resume(this_future)
  end
  local args = {UNIX and '-c' or '/C', command}
  local stdout, stderr = uv_new_pipe(false), uv_new_pipe(false)
  local proc, pid = uv_spawn(shell_program, {args = args,
    stdio = {nil, stdout, stderr}, hide = true}, on_exit)
  if not proc then
    return nil, diagnostics.new("child_process_error: spawn failed: ${1}", pid)
  end
  local out_buff, err_buff = {}, {}
  uv_read_start(stdout, function(err, data)
    if data then out_buff[#out_buff+1] = data end
  end)
  uv_read_start(stderr, function(err, data)
    if data then err_buff[#err_buff+1] = data end
  end)
  co_yield()
  uv_close(proc)
  out_buff, err_buff = from_text_stream(out_buff), from_text_stream(err_buff)
  if exit_status ~= 0 or exit_signal ~= 0 then
    local reason = (exit_signal == 0 and 'failed' or 'interrupted')
    return nil, diagnostics.new{'child_process_error: command ${reason} '..
      '(${exit_status}/${signal}): ${stderr}', reason = reason,
      exit_status = exit_status, signal = exit_signal,
      stdout = out_buff, stderr = err_buff}
  end
  return out_buff, err_buff
end

------------------------------------------------------------------------------
-- Module Initialization
------------------------------------------------------------------------------

return {
  UNIX = UNIX,
  WINDOWS = WINDOWS,
  sh = sh,
}
