------------------------------------------------------------------------------
-- Asynchronous programming based on coroutines and futures
------------------------------------------------------------------------------

local assert, next, rawget = assert, next, rawget
local setmetatable = setmetatable
local co_create = coroutine.create
local co_resume = coroutine.resume
local co_yield = coroutine.yield
local co_running = coroutine.running

local diagnostics = require 'lift.diagnostics'
local pcall = diagnostics.pcall

local uv = require 'lluv'
local uv_run, uv_timer, uv_now = uv.run, uv.timer, uv.now
local UV_RUN_ONCE = uv.RUN_ONCE

------------------------------------------------------------------------------
-- Coroutine (thread) Pool
------------------------------------------------------------------------------

local coroutines = {} -- list of free coroutines + map{co = future}
local execute -- called to execute a future
local on_done -- called with the results of pcall(execute(future))

-- Reusable coroutine function. Calls execute(future) in cycles.
local function thread_f(future)
  ::start::
  local ok, res = pcall(execute, future)
  on_done(future, ok, res)
  future = co_yield(res)
  goto start
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

local resumable = {}  -- map{future = arg} of threads ready to run

-- Schedules a coroutine to be resumed with `arg` as soon as possible.
local function schedule(future, arg)
  resumable[future] = arg or false
end

-- Runs all threads until they're either blocked or done.
local function step()
  ::start::
  local future, arg = next(resumable)
  if not future then return end
  local co = future.co
  if not co then -- start a new thread
    co = co_alloc(future)
    future.co = co
  end
  local ok, err = co_resume(co, arg)
  if not ok then error('error in future:on_ready callback: '..tostring(err)) end
  resumable[future] = nil
  goto start
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

-- Adds a function to be called when the future's thread finishes.
-- Arguments passed to callback: future, error (or nil), results (table, or nil)
function Future:on_ready(callback)
  if self.ready then -- call callback immediately
    callback(self, self.error, rawget(self, 'results'))
  else
    self[#self+1] = callback
  end
end

-- Called by coroutines to execute a future.
execute = function(future)
  return {future.f(future.arg)}
end

-- Called by coroutines when a future completes execution.
on_done = function(future, ok, res)
  future.ready = true
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
  -- only reuse coroutine if callbacks didn't raise errors
  co_free(future.co, future)
end

------------------------------------------------------------------------------
-- Module Functions
------------------------------------------------------------------------------

-- Schedules a function to be called asynchronously as `f(arg)` in a coroutine.
-- Returns a future object for interfacing with the async call.
local function async(f, arg)
  local future = setmetatable({f = f, arg = arg,
    co = false, ready = false, results = false}, Future)
  resumable[future] = future
  return future
end

-- Runs all async functions to completion. Call this from the main thread.
local function run()
  repeat step() until uv_run(UV_RUN_ONCE) == 0
  step() -- handles final events
end

-- Forces run() to stop while there are still threads waiting for events.
-- May cause leaks and bugs. Only call if you want to terminate the application.
local function stop()
  uv.handles(function(handle) handle:close() end)
end

-- Suspends the calling thread until `future` becomes ready, or until `timeout`
-- milliseconds have passed. The timeout is optional, and if specified it
-- should be a positive integer. If the future is fulfilled, wait() returns
-- true and the future's results table; if wait() times out, it returns false.
-- If the future raises an error, wait() propagates the error.
local function wait(future, timeout)
  local results = future.results
  if results then return true, results end
  local this_future = co_get()
  if future == this_future then error('future cannot wait for itself', 2) end
  if timeout then
    local timer = uv_timer()
    local function callback(future_or_timer, err, res)
      if timer == nil then return end -- ignore second call
      if future_or_timer == timer then res = 'timed out' end
      schedule(this_future, res)
      timer:close()
      timer = nil
    end
    timer:start(timeout, callback)
    future:on_ready(callback)
    results = co_yield()
    if results == 'timed out' then return false end
  else
    future:on_ready(function(_, err, res)
      schedule(this_future, res)
    end)
    results = co_yield()
  end
  if not results then error(future.error) end
  return true, results
end

-- Suspends the calling thread until one future from the list becomes ready.
-- Either returns the first fulfilled future, or raises the first raised error.
local function wait_any(futures)
  -- first we check if any future is currently ready
  local n, this_future = #futures, co_get()
  for i = 1, n do
    local f = futures[i]
    if f == this_future then error('future cannot wait for itself', 2) end
    if f.results then return f end -- this will also raise any error
  end
  local done, first_err = false
  local function callback(future, err, res)
    if done then return end
    done = true
    first_err = err
    schedule(this_future, future)
  end
  for i = 1, n do
    futures[i]:on_ready(callback)
  end
  local first = co_yield()
  if first_err then error(first_err) end
  return first
end

-- used by wait_all() as diagnostic:format()
local function format_errors(d)
  local loc, nested = d.location, d.nested
  local s = loc.file..':'..loc.line..': '..d.message
  for i = 1, #nested do
    s = s..'\n  ('..i..') '..tostring(nested[i])
  end
  return s
end

-- Suspends the calling thread until all futures in the list become ready.
-- If at least one future raises an error, wait_all() will raise an aggregate
-- error (a diagnostic) object that lits all errors raised by the futures.
local function wait_all(futures)
  local n, errors, this_future = #futures, nil, co_get()
  local function callback(future, err, res)
    if err then
      if not errors then errors = {err} else errors [#errors+1] = err end
    end
    n = n - 1
    if n == 0 then schedule(this_future) end
  end
  for i = 1, n do
    local f = futures[i]
    if f == this_future then error('future cannot wait for itself', 2) end
    f:on_ready(callback)
  end
  if n > 0 then co_yield() end
  if errors then
    local d = diagnostics.new('fatal: wait_all() caught '):function_location(2)
    d[0] = d[0]..#errors..(#errors > 1 and ' errors' or ' error')
    d.nested = errors
    d.format = format_errors
    error(d)
  end
end

-- Suspends the calling thread until `dt` milliseconds have passed.
-- Returns the elapsed time spent sleeping, in milliseconds.
local function sleep(dt)
  local timer, this_future = uv_timer(), co_get()
  timer:start(dt, function() schedule(this_future) end)
  local t0 = uv_now()
  co_yield()
  timer:close()
  return uv_now() - t0
end

------------------------------------------------------------------------------
-- Module Table
------------------------------------------------------------------------------

return setmetatable({
  async = async,
  run = run,
  sleep = sleep,
  stop = stop,
  wait = wait,
  wait_all = wait_all,
  wait_any = wait_any,
}, {__call = function(M, f, arg) -- calling the module == calling async()
  return async(f, arg)
end})
