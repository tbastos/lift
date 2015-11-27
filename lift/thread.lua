------------------------------------------------------------------------------
-- Threading Module (based on coroutines and futures)
------------------------------------------------------------------------------

local assert, next = assert, next
local setmetatable = setmetatable
local co_create = coroutine.create
local co_resume = coroutine.resume
local co_yield = coroutine.yield
local co_running = coroutine.running

local lstr_format = require('lift.string').format
local uv = require 'lluv'

------------------------------------------------------------------------------
-- Coroutine (thread) Pool
------------------------------------------------------------------------------

local coroutines = {} -- list of free coroutines, and also a map{co = future}

-- Reusable coroutine function.
local function thread_f(f, arg, on_done)
  while f do
    -- on_done is yielded to indicate that f(arg) finished
    f, arg, on_done = co_yield(on_done, {f(arg)})
  end
end

-- Allocates a coroutine to a future. Returns a Lua thread.
local function co_alloc(future)
  local n, co = #coroutines
  if n > 0 then
    co = coroutines[n]
    coroutines[n] = nil
  else
    co = co_create(thread_f)
  end
  coroutines[co] = future
  return co
end

-- Deallocates a coroutine currently allocated to a future.
local function co_free(co, future)
  coroutines[#coroutines+1] = co
  coroutines[future] = nil
end

-- Returns the currently running future and coroutine.
-- Must be called from within a coroutine created by this module.
local function co_get()
  local co = co_running()
  return assert(coroutines[co], 'not in a lift.thread coroutine'), co
end

------------------------------------------------------------------------------
-- Future (promise for an async function call executed in a coroutine)
------------------------------------------------------------------------------

local Future = {} -- Future metatable
local ready = {}  -- map{future = coroutine/false} of calls ready to run

function Future:__tostring()
  return 'lift.thread.Future('..tostring(self.f)..', '..lstr_format(self.arg)..')'
end

-- Schedules a function to be called asynchronously as `f(arg)` in a coroutine.
-- Returns a future that can be used to wait and retrieve the function results.
local function spawn(f, arg)
  local future = setmetatable({f = f, arg = arg,
    co = false, results = false}, Future)
  ready[future] = false
  return future
end

-- Returns whether a future was fulfilled.
-- TODO: If the coroutine raised an error, this function raises the error.
local function check(future)
  return future.results ~= false
end

-- Schedules a coroutine to run again.
local function set_ready(future, co)
  ready[future] = co or future.co
end

local function add_waiter(waiter, future)
  local t = future.waiters
  if not t then t = {} ; future.waiters = t end
  t[#t+1] = waiter
end

-- Called when a future is fulfilled.
local function on_done(future, res)
  future.results = res
  co_free(future.co, future)
  local waiters = future.waiters
  if waiters then
    for i = 1, #waiters do
      set_ready(waiters[i])
    end
  end
end

------------------------------------------------------------------------------
-- Timers
------------------------------------------------------------------------------

local timers = {} -- map{timer = future}

local function on_timeout(timer)
  timer:stop()
  local future = timers[timer]
  timers[timer] = nil
  set_ready(future)
end

-- Suspends the current coroutine and resumes milliseconds later.
-- Returns the actual dt spent sleeping and the current timestamp in ms.
local function sleep(milliseconds)
  local future = co_get()
  local timer = uv.timer()
  timer:start(milliseconds, on_timeout)
  timers[timer] = future
  local t0 = uv.now()
  co_yield()
  local now = uv.now()
  return now - t0, now
end

------------------------------------------------------------------------------
-- Scheduler
------------------------------------------------------------------------------

-- Runs until all threads are either waiting or done.
local function step()
  while true do
    local future, co = next(ready)
    if not future then return end
    local ok, action, res
    if co then -- resume a running coroutine
      ok, action, res = co_resume(co)
    else -- start running a new coroutine
      co = co_alloc(future)
      future.co = co
      ok, action, res = co_resume(co, future.f, future.arg, on_done)
    end
    if not ok then
      error('coroutine raised error: '..tostring(action))
    elseif action then
      action(future, res)
    end
    ready[future] = nil
  end
end

-- Runs all scheduled functions to completion. Call this from the main thread.
local function run()
  repeat step() until uv.run(uv.RUN_ONCE) == 0
  step() -- handles final events
end

-- Suspends the current coroutine until the given `future` is fulfilled,
-- or until `timeout` milliseconds have passed. The timeout is optional.
-- Returns true if the future was fulfilled, false if timed out.
local function wait(future, timeout)
  local this_future, this_co = co_get()
  if future == this_future then return true end -- never wait for itself
  add_waiter(this_future, future)
  co_yield()
  return check(future)
end

local function wait_all(futures, timeout)
  -- TODO
end

------------------------------------------------------------------------------
-- Module Table
------------------------------------------------------------------------------

return {
  run = run,
  sleep = sleep,
  spawn = spawn,
  step = step,
  wait = wait,
}
