------------------------------------------------------------------------------
-- Task Engine
------------------------------------------------------------------------------

local tostring, type = tostring, type
local getmetatable, setmetatable = getmetatable, setmetatable
local unpack = table.unpack or unpack -- LuaJIT compatibility
local str_find, str_gmatch, str_match = string.find, string.gmatch, string.match
local tbl_concat, tbl_sort = table.concat, table.sort
local dbg_getlocal = debug.getlocal

local inspect = require'lift.util'.inspect
local diagnostics = require 'lift.diagnostics'

local async = require 'lift.async'
local async_get, await, wait_all = async._get, async.wait, async.wait_all

------------------------------------------------------------------------------
-- Graph construction and cycle detection
------------------------------------------------------------------------------

local roots = {} -- list of root task futures (called from non-task threads)

-- Adds an edge to the graph of task (future) calls.
local function on_call(from_future, from_task, to_future, to_task)
  if not from_task then
    roots[#roots + 1] = to_future
  else
    local t = from_future.calls
    t[#t+1] = to_future
  end
end

-- Finds the first cycle in the graph of task futures.
-- Returns nil if no cycle is found, or a circular path {a, ..., a} otherwise.
local function visit(future, visited, dist)
  if visited[future] then -- found cycle
    visited[dist + 1] = future
    return visited
  end
  visited[future] = dist
  dist = dist + 1
  local calls = future.calls
  for i = 1, #calls do
    local cycle = visit(calls[i], visited, dist)
    if cycle then cycle[dist] = future return cycle end
  end
  visited[future] = nil
end
local function find_cycle()
  local visited = {}
  for i = 1, #roots do
    local cycle = visit(roots[i], visited, 0)
    if cycle then return cycle end
  end
end

------------------------------------------------------------------------------
-- Task (memoized async function with a single argument and multiple results)
------------------------------------------------------------------------------

local Task = {
  name = '?', -- unique, fully qualified name
}

Task.__index = Task

Task.__call = diagnostics.trace(
  '[task] running ${self} ${arg}',
  '[task] finished ${self} ${arg}',
  function(self, arg, extra)
    local future = self:async(arg, extra)
    local ok, res = await(future)
    if not ok then
      res:report()
    end
    return unpack(res)
  end)

function Task.__tostring(task)
  local prefix = tostring(task.ns)
  return prefix..(prefix == '' and '' or '.')..task.name
end

local function get_or_start(self, arg, extra)
  local futures = self.futures
  local future = futures[arg or 1]
  if future then return future end -- already started
  -- check if the task was called correctly
  local ns = self.ns
  if arg == ns then
    error('task must be called as .function() not :method()', 4)
  end
  if extra ~= nil then error('tasks can only take one argument', 4) end
  -- start the task
  future = async(self.f, arg)
  future.task = self
  future.calls = {} -- list of calls to other task futures
  futures[arg or 1] = future
  return future
end

local function format_cycle(d)
  local path = d.cycle
  local msg = tostring(path[1].task)
  for i = 2, #path do
    msg = msg .. ' -> ' .. tostring(path[i].task)
  end
  return msg
end

function Task:async(arg, extra)
  local future = get_or_start(self, arg, extra)
  local running_future = async_get()
  local running_task = running_future.task
  on_call(running_future, running_task, future, self)
  if future:is_running() then -- this is a cycle
    diagnostics.new{'fatal: cycle detected in tasks: ${format_cycle}',
      cycle = find_cycle(), format_cycle = format_cycle}:set_location(3):report()
  end
  return future
end

function Task:get_results(arg)
  local future = self.futures[arg or 1]
  return future and future.results
end

local function validate_name(name)
  if type(name) ~= 'string' or str_find(name, '^%a[_%w]*$') == nil then
    error('expected a task name, got '..inspect(name), 4)
  end
end

local function new_task(ns, name, f)
  validate_name(name)
  if type(f) ~= 'function' then
    error('expected a function, got '..inspect(f), 3)
  end
  local param = dbg_getlocal(f, 1)
  if param == 'self' then
    error('tasks must be declared as .functions() not :methods()', 3)
  end
  return setmetatable({ns = ns, name = name, f = f, futures = {false}}, Task)
end

------------------------------------------------------------------------------
-- TaskList object (callable list of tasks)
------------------------------------------------------------------------------

local TaskList = {}

TaskList.__call = diagnostics.trace(
  '[task] running ${self} ${arg}',
  '[task] finished ${self} ${arg}',
  function(self, arg, extra)
    local t = {}
    for i = 1, #self do
      t[i] = self[i]:async(arg, extra)
    end
    local ok, err = wait_all(t)
    if not ok then
      if #err.nested == 1 then err = err.nested[1] end
      err:report()
    end
  end)

function TaskList:__tostring()
  local t = {}
  for i = 1, #self do
    t[i] = tostring(self[i])
  end
  tbl_sort(t)
  return 'task list {'..tbl_concat(t, ', ')..'}'
end

------------------------------------------------------------------------------
-- Namespace (has an unique name; contains tasks and methods)
------------------------------------------------------------------------------

local Namespace = {
  name = '?',    -- unique name within its parent
  tasks = nil,   -- tasks map {name = task}
  parent = nil,  -- namespace hierarchy
  nested = nil,  -- nested namespaces map {name = child_namespace}
}

local function new_namespace(name, parent)
  return setmetatable({name = name, parent = parent, tasks = {}, nested = {}}, Namespace)
end

function Namespace.__index(t, k)
  return t.tasks[k] or Namespace[k] or t.nested[k]
end

function Namespace.__newindex(t, k, v)
  t.tasks[k] = new_task(t, k, v)
end

function Namespace.__call(namespace, t)
  local tp = type(t)
  if tp ~= 'table' then error('expected a table, got '..tp, 2) end
  for i = 1, #t do
    if getmetatable(t[i]) ~= Task then
      error('element #'..i..' is not a Task, but a '..type(t[i]))
    end
  end
  return setmetatable(t, TaskList)
end

function Namespace.__tostring(ns)
  local parent = ns.parent
  if not parent then return ns.name end
  if not parent.parent then return ns.name end
  return tostring(parent)..'.'..ns.name
end

function Namespace:namespace(name)
  validate_name(name)
  local child = new_namespace(name, self)
  self.nested[name] = child
  return child
end

function Namespace:get_namespace(name)
  local g = self
  for s in str_gmatch(name, '([^.]+)%.?') do
    local child = g.nested[s]
    if not child then
      diagnostics.report("fatal: no such namespace '${1}.${2}'", g, s)
    end
    g = child
  end
  return g
end

function Namespace:get_task(name)
  local gn, tn = str_match(name, '^(.-)%.?([^.]+)$')
  local task = self:get_namespace(gn).tasks[tn]
  if not task then
    diagnostics.report("fatal: no such task '${1}'", name)
  end
  return task
end

function Namespace:reset(args)
  self.tasks = {}
  self.nested = {}
end

-- internal symbols:
Namespace._Task = Task
function Namespace._get_roots() return roots end

-- return root task namespace
return new_namespace('')
