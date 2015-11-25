------------------------------------------------------------------------------
-- Coroutine Scheduler
------------------------------------------------------------------------------

local assert, next = assert, next
local setmetatable = setmetatable
local co_create = coroutine.create
local co_resume = coroutine.resume
local co_yield = coroutine.yield
local co_running = coroutine.running

local uv = require 'lluv'

------------------------------------------------------------------------------
-- Coroutine Pool
------------------------------------------------------------------------------

local coroutines = {} -- list of free coroutines and map{co = owner}

local function thread_f(f, arg, on_finished)
  while f do
    -- we yield on_finished to indicate that f(arg) finished
    f, arg, on_finished = co_yield(on_finished, {f(arg)})
  end
end

local function co_alloc(owner)
  local n, co = #coroutines
  if n > 0 then
    co = coroutines[n]
    coroutines[n] = nil
  else
    co = co_create(thread_f)
  end
  coroutines[co] = owner
  return co
end

local function co_free(co, owner)
  coroutines[#coroutines+1] = co
  coroutines[owner] = nil
end

------------------------------------------------------------------------------
-- Task objects (abstraction over coroutines, to wait for events, etc.)
------------------------------------------------------------------------------

local Task = {}     -- Task class (no relation to a lift.task task!)
local ready = {}    -- map{task = true} of tasks ready to run

function Task:__tostring()
  return 'lift.scheduler.task{}'
end

local function on_task_finished(task, res)
  task.results = res
  co_free(task.co, task)
end

local function suspend(task)
  co_yield()
end

local function set_ready(task)
  ready[task] = true
end

local function run_task(task)
  local co, ok, event, res = task.co
  if co then -- resume a running task
    ok, event, res = co_resume(co)
  else -- start running a new task
    co = co_alloc(task)
    task.co = co
    ok, event, res = co_resume(co, task.f, task.arg, on_task_finished)
  end
  if not ok then
    error('coroutine raised error: '..tostring(event))
  elseif event then
    event(task, res)
  end
  ready[task] = nil
end

-- TODO: wait(task[, timeout]), wait_all{tasks}, wait_any{tasks}

------------------------------------------------------------------------------
-- Scheduler
------------------------------------------------------------------------------

-- Returns the currently running task. Must be called from within a task.
local function get_current_task()
  return assert(coroutines[co_running()], 'unknown task/coroutine')
end

-- Creates a task to call `f(arg)` in a coroutine. Returns the task object.
local function spawn(f, arg)
  local task = setmetatable({f = f, arg = arg,
    co = false, results = false}, Task)
  ready[task] = true
  return task
end

-- Runs tasks until all are either waiting or done.
local function step()
  while true do
    local task = next(ready)
    if not task then return end
    run_task(task)
  end
end

-- Called from the main thread to run all tasks to completion.
local function run()
  repeat step() until uv.run(uv.RUN_ONCE) == 0
  step() -- handles final events
end

------------------------------------------------------------------------------
-- Timers
------------------------------------------------------------------------------

local timers = {} -- map{timer = task}

local function on_timeout(timer)
  timer:stop()
  local task = timers[timer]
  timers[timer] = nil
  set_ready(task)
end

-- Suspend the current task and resume dt_ms milliseconds later.
-- Returns the actual dt_ms spent sleeping and the current timestamp in ms.
local function sleep(dt_ms)
  local task = get_current_task()
  local timer = uv.timer()
  timer:start(dt_ms, on_timeout)
  timers[timer] = task
  local t0 = uv.now()
  suspend(task)
  local now = uv.now()
  return now - t0, now
end

------------------------------------------------------------------------------
-- Module Table
------------------------------------------------------------------------------

return {
  run = run,
  sleep = sleep,
  spawn = spawn,
  step = step,
}
