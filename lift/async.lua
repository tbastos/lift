------------------------------------------------------------------------------
-- Module for asynchronous programming based on coroutines and futures
------------------------------------------------------------------------------

local assert, next = assert, next
local setmetatable = setmetatable
local co_create = coroutine.create
local co_resume = coroutine.resume
local co_yield = coroutine.yield
local co_running = coroutine.running

local diagnostics = require 'lift.diagnostics'
local pcall = diagnostics.pcall

local uv = require 'lluv' -- needed for timer callbacks (sleep/timeout)

------------------------------------------------------------------------------
-- Coroutine (thread) Pool
------------------------------------------------------------------------------

local coroutines = {} -- list of free coroutines, and also a map{co = future}
local execute   -- called to execute a future
local on_done   -- called when a future is fulfilled
local on_error  -- called when a future is rejected (i.e. it raised an error)

-- Reusable coroutine function. Calls dispatch(future) in cycles.
local function thread_f(future)
  while true do
    assert(future, "thread_f has no future")
    local ok, res = pcall(execute, future)
    local event = ok and on_done or on_error
    event(future, res)
    future = co_yield(res)
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
  return assert(coroutines[co], 'not in a lift.async coroutine'), co
end

------------------------------------------------------------------------------
-- Timers
------------------------------------------------------------------------------

local timers = {} -- map{timer = future}

local function add_timer(milliseconds, future, action)
  assert(future.timer == nil, 'two timers for the same future?')
  local timer = uv.timer()
  timer:start(milliseconds, action)
  timers[timer] = future
  future.timer = timer
  return timer
end

local function remove_timer(timer, future)
  future.timer = nil
  timers[timer] = nil
  timer:close()
end

------------------------------------------------------------------------------
-- Scheduler
------------------------------------------------------------------------------

local ready = {}  -- map{future = coroutine/false} of calls ready to run

-- Schedules a coroutine to be resumed as soon as possible.
local function set_ready(future, co)
  ready[future] = co or future.co
end

-- Runs until all threads are either blocked or done.
local function step()
  while true do
    local future, co = next(ready)
    if not future then return end
    local ok, err
    if co then -- resume a running coroutine
      ok, err = co_resume(co)
    else -- start running a new coroutine
      co = co_alloc(future)
      future.co = co
      ok, err = co_resume(co, future)
    end
    if not ok then error('unexpected coroutine error: '..tostring(err)) end
    ready[future] = nil
  end
end

------------------------------------------------------------------------------
-- Future (proxy object for an async function call executed in a coroutine)
------------------------------------------------------------------------------

local Future = {} -- Future class
Future.__index = Future

function Future:__tostring()
  return 'lift.async.Future('..tostring(self.f)..', '..tostring(self.arg)..')'
end

-- Kills a running coroutine. This is dangerous and can easily cause bugs!
-- Useful for tests. Only call you *really* know what you're doing.
function Future:abort()
  ready[self] = nil
  local co, timer = self.co, self.timer
  if co then coroutines[co] = nil end
  if timer then remove_timer(timer, self) end
end

-- Adds a function to be called when the future's thread finishes.
-- Callback arguments: future, error (or nil), results (table, or nil)
function Future:after(callback)
  self[#self+1] = callback
end

-- Called by coroutines to execute a future.
execute = function(future)
  return {future.f(future.arg)}
end

-- Called when a future is fulfilled.
on_done = function(future, res)
  future.results = res
  co_free(future.co, future)
  local waiters = future.waiters
  if waiters then
    while true do
      local w = next(waiters)
      if not w then break end
      waiters[w] = nil
      local n = w.waiting
      w.waiting = n - 1
      if n == 1 then set_ready(w) end
    end
  end
end

-- Called when an error is raised in a coroutine.
on_error = function(future, err)
end

-- Called when a timer rings.
local function on_timeout(timer)
  local future = timers[timer]
  remove_timer(timer, future)
  set_ready(future)
end

------------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------------

-- Schedules a function to be called asynchronously as `f(arg)` in a coroutine.
-- Returns a future object for interfacing with the async call.
local function async(f, arg)
  local future = setmetatable({f = f, arg = arg,
    co = false, results = false}, Future)
  ready[future] = false
  return future
end

-- Runs all async functions to completion. Call this from the main thread.
local function run()
  repeat step() until uv.run(uv.RUN_ONCE) == 0
  step() -- handles final events
end

-- Suspends the calling thread until the given `future` is fulfilled,
-- or until `timeout` milliseconds have passed (timeout is optional).
-- Returns true if the future was fulfilled; false if an error ocurred or
-- if wait() timed out. Returns the error or "timed out" as second result.
local function wait(future, timeout)
  local this_future = co_get()
  if future == this_future then return true end -- never wait for itself
  local waiters = future.waiters
  if not waiters then waiters = {} ; future.waiters = waiters end
  waiters[this_future] = true
  this_future.waiting = 1
  if timeout then
    local timer = add_timer(timeout, this_future, on_timeout)
    co_yield()
    if waiters[this_future] then -- timed out
      waiters[this_future] = nil
      return false, 'timed out'
    else -- fulfilled
      remove_timer(timer, this_future)
    end
  else
    co_yield()
  end
  -- TODO: If the coroutine raised an error, raise the error here?
  return true
end

local function wait_all(futures, timeout)
  local n, this_future = #futures, co_get()
  for i = 1, n do
    local f = futures[i]
    if f == this_future then error('future cannot wait for itself', 2) end
    local waiters = f.waiters
    if not waiters then waiters = {} ; f.waiters = waiters end
    waiters[this_future] = true
  end
  this_future.waiting = n
  if timeout then
    local timer = add_timer(timeout, this_future, on_timeout)
    co_yield()
    if timers[timer] == nil then -- timed out
      for i = 1, n do
        futures[i].waiters[this_future] = nil
      end
      return false
    else
      remove_timer(timer, this_future)
    end
  else
    co_yield()
  end
  -- TODO: If the coroutine raised an error, raise the error here?
  return true
end

-- Suspends the current coroutine and resumes milliseconds later.
-- Returns the actual dt spent sleeping and the current timestamp in ms.
local function sleep(milliseconds)
  add_timer(milliseconds, co_get(), on_timeout)
  local t0 = uv.now()
  co_yield()
  local now = uv.now()
  return now - t0, now
end

------------------------------------------------------------------------------
-- Module Table
------------------------------------------------------------------------------

return setmetatable({
  async = async,
  run = run,
  sleep = sleep,
  wait = wait,
  wait_all = wait_all,
}, {__call = function(M, f, arg) -- calling the module == calling async()
  return async(f, arg)
end})
