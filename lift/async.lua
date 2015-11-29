------------------------------------------------------------------------------
-- Asynchronous programming based on coroutines and futures
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

local coroutines = {} -- list of free coroutines + map{co = future}
local execute -- called to execute a future
local on_done -- called with the result of execute, or an error

-- Reusable coroutine function. Calls execute(future) in cycles.
local function thread_f(future)
  while true do
    local ok, res = pcall(execute, future)
    on_done(future, ok, res)
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
-- Scheduler
------------------------------------------------------------------------------

local ready = {}  -- map{future = coroutine/false} of calls ready to run

-- Schedules a coroutine to be resumed as soon as possible.
local function set_ready(future, value)
  ready[future] = value or false
end

-- Runs all threads until they're either blocked or done.
local function step()
  while true do
    local future, value = next(ready)
    if not future then return end
    local co = future.co
    if not co then -- start a new thread
      co = co_alloc(future)
      future.co = co
    end
    local ok, err = co_resume(co, value)
    if not ok then error('error in future:when_done callback: '..tostring(err)) end
    ready[future] = nil
  end
end

------------------------------------------------------------------------------
-- Future (proxy object for an async function call executed in a coroutine)
------------------------------------------------------------------------------

local Future = {} -- Future class

function Future.__index(t, k)
  -- accessing .results in a rejected future raises its error
  if k == 'results' then error(t.error) end
  return Future[k]
end

function Future:__tostring()
  return 'lift.async.Future('..tostring(self.f)..', '..tostring(self.arg)..')'
end

-- Kills a running coroutine. This is dangerous and only meant for tests!
-- Only call you *really* know what you're doing.
function Future:abort()
  ready[self] = nil
  local co = self.co
  if co then coroutines[co] = nil end
end

-- Adds a function to be called when the future's thread finishes.
-- Arguments passed to callback: future, error (or nil), results (table, or nil)
function Future:when_done(callback)
  self[#self+1] = callback
end

-- Called by coroutines to execute a future.
execute = function(future)
  return {future.f(future.arg)}
end

-- Called by coroutines when a future completes execution.
on_done = function(future, ok, res)
  local cb_err, cb_res -- callback arguments
  if ok then -- future was fulfilled
    cb_res = res
    future.results = res
  else -- future raised an error
    cb_err = res
    future.results = nil
    future.error = res
  end
  -- call callbacks
  for i = 1, #future do
    future[i](future, cb_err, cb_res)
  end
  -- only reuse the coroutine if callbacks didn't raise an error
  co_free(future.co, future)
end

------------------------------------------------------------------------------
-- Module Functions
------------------------------------------------------------------------------

-- Schedules a function to be called asynchronously as `f(arg)` in a coroutine.
-- Returns a future object for interfacing with the async call.
local function async(f, arg)
  local future = setmetatable({f = f, arg = arg,
    co = false, results = false}, Future)
  ready[future] = future
  return future
end

-- Runs all async functions to completion. Call this from the main thread.
local function run()
  repeat step() until uv.run(uv.RUN_ONCE) == 0
  step() -- handles final events
end

-- Suspends the calling thread until `future` is fulfilled, or until `timeout`
-- milliseconds have passed. The timeout is optional, and if specified it
-- should be a positive integer. If the future is fulfilled, wait() returns
-- true and the future's results table; if wait() times out, it returns false.
-- If the future raises an error, wait() raises the error.
local function wait(future, timeout)
  local results = future.results
  if results then return true, results end
  local this_future = co_get()
  if future == this_future then error('future cannot wait for itself', 2) end
  if timeout then
    local timer = uv.timer()
    local function callback(future_or_timer, err, res)
      if timer == nil then return end -- ignore second call
      if future_or_timer == timer then res = 'timed out' end
      set_ready(this_future, res)
      timer:close()
      timer = nil
    end
    timer:start(timeout, callback)
    future:when_done(callback)
    results = co_yield()
    if results == 'timed out' then return false end
  else
    future:when_done(function(_, err, res)
      set_ready(this_future, res)
    end)
    results = co_yield()
  end
  if not results then error(future.error) end
  return true, results
end

-- Suspends the calling thread until any future in the list finishes.
-- Returns the first fulfilled future, or raises the first raised error.
local function wait_any(futures)
  -- TODO
end

-- Suspends the calling thread until all futures in the list finish execution.
-- Raises an error if at least one future raises an error. In this case, the
-- raised error aggregates all errors raised by the listed futures.
local function wait_all(futures)
  local n, e, this_future = #futures, nil, co_get()
  local function callback(future, err, res)
    if n == 1 then set_ready(this_future) end
    n = n - 1
  end
  for i = 1, n do
    local f = futures[i]
    if f == this_future then error('future cannot wait for itself', 2) end
    f:when_done(callback)
  end
  co_yield()
  if e then error(e) end
end

-- Suspends the current coroutine and resumes milliseconds later.
-- Returns the time spent sleeping and the current timestamp, in milliseconds.
local function sleep(milliseconds)
  local timer, this_future = uv.timer(), co_get()
  timer:start(milliseconds, function()
    set_ready(this_future)
  end)
  local t0 = uv.now()
  co_yield()
  local now = uv.now()
  timer:close()
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
  wait_any = wait_any,
}, {__call = function(M, f, arg) -- calling the module == calling async()
  return async(f, arg)
end})
