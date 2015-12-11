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
local await, wait_all = async.wait, async.wait_all

------------------------------------------------------------------------------
-- Helper Functions
------------------------------------------------------------------------------

local function get_or_start(task, arg, extra)
  local futures = task.futures
  local future = futures[arg or 1]
  if future then return future end -- currently running
  -- check if the task was called correctly
  local ns = task.ns
  if arg == ns then
    error('tasks must be called as .functions() not :methods()', 3)
  end
  if extra ~= nil then error('tasks can only take one argument', 3) end
  -- start the task
  future = async(task.f, arg)
  future.task = task
  futures[arg or 1] = future
  return future
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
      t[i] = get_or_start(self[i], arg, extra)
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
    local future = get_or_start(self, arg, extra)
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

-- return root task namespace
return new_namespace('')
