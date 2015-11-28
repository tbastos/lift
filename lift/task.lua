------------------------------------------------------------------------------
-- Task Engine
------------------------------------------------------------------------------

local tostring, type, unpack = tostring, type, table.unpack
local getmetatable, setmetatable = getmetatable, setmetatable
local str_find, str_gmatch, str_match = string.find, string.gmatch, string.match
local tbl_concat, tbl_sort = table.concat, table.sort

local diagnostics = require 'lift.diagnostics'
local lstr_format = require('lift.string').format

------------------------------------------------------------------------------
-- TaskSet object (callable set of tasks)
------------------------------------------------------------------------------

local TaskSet = {}

function TaskSet.__call(cs, ...)
  for i = 1, #cs do
    cs[i](...)
  end
end

function TaskSet.__tostring(cs)
  local t = {}
  for i = 1, #cs do
    t[i] = tostring(cs[i])
  end
  tbl_sort(t)
  return 'lift.task{'..tbl_concat(t, ', ')..'}'
end

------------------------------------------------------------------------------
-- Task object (memoized function)
------------------------------------------------------------------------------

local Task = {
  name = '?',
}

Task.__index = Task

function Task.__call(task, arg, extra)
  local res = task.res[arg or 1]
  if not res then
    -- check if the task was called correctly
    local group = task.group
    if arg == group then
      error('tasks must be called as .functions() not :methods()', 2)
    end
    if extra ~= nil then error('tasks can only take one argument', 2) end
    -- call the function and save the results
    res = {task.f(group, arg)}
    task.res[arg or 1] = res
  end
  return unpack(res)
end

function Task.__tostring(task)
  local prefix = tostring(task.group)
  return prefix..(prefix == '' and '' or ':')..task.name
end

function Task:get_result_for(arg)
  return self.res[arg or 1]
end

local function validate_name(name)
  if type(name) ~= 'string' or str_find(name, '^%a[_%w]*$') == nil then
    error('expected a task name, got '..lstr_format(name), 3)
  end
end

local dbg_getlocal = require('debug').getlocal
local function validate_f(f)
  if type(f) ~= 'function' then
    error('expected a function, got '..lstr_format(f), 2)
  end
  if _ENV then -- in Lua 5.2+ we check whether f is a method
    local name = dbg_getlocal(f, 1)
    if name ~= 'self' then
      error('tasks must be declared as :methods() not .functions()')
    end
  end
end

local function new_task(group, name, f)
  validate_name(name) ; validate_f(f)
  return setmetatable({group = group, name = name, f = f, res = {false}}, Task)
end

------------------------------------------------------------------------------
-- Group object (has name, methods, tasks and dependencies)
------------------------------------------------------------------------------

local Group = {
  name = '?',       -- unique name within its parent
  tasks = nil,      -- tasks map {name = task}
  parent = nil,     -- group hierarchy
  children = nil,   -- subgroups map {name = child_group}
  requires = nil,   -- list of groups required by this group
}

local function new_group(name, parent)
  return setmetatable({name = name, parent = parent,
    tasks = {}, children = {}, requires = {}}, Group)
end

function Group.__index(t, k)
  return t.tasks[k] or Group[k] or t.children[k]
end

function Group.__newindex(t, k, v)
  t.tasks[k] = new_task(t, k, v)
end

function Group.__call(group, t)
  local tp = type(t)
  if tp ~= 'table' then error('expected a table, got '..tp, 2) end
  for i = 1, #t do
    if getmetatable(t[i]) ~= Task then
      error('element #'..i..' is not a Task, but a '..type(t[i]))
    end
  end
  return setmetatable(t, TaskSet)
end

function Group.__tostring(group)
  local parent = group.parent
  if not parent then return group.name end
  if not parent.parent then return group.name end
  return tostring(parent)..'.'..group.name
end

function Group:group(name)
  validate_name(name)
  local child = new_group(name, self)
  self.children[name] = child
  return child
end

function Group:get_group(name)
  local g = self
  for s in str_gmatch(name, '([^.:]+)[.:]*') do
    local child = g.children[s]
    if not child then
      diagnostics.report("fatal: no such group '"..tostring(g)..'.'..s.."'")
    end
    g = child
  end
  return g
end

function Group:get_task(name)
  local gn, tn = str_match(name, '^(.-)[.:]*([^.:]+)$')
  local task = self:get_group(gn).tasks[tn]
  if not task then
    diagnostics.report("fatal: no such task '"..name.."'")
  end
  return task
end

function Group:reset(args)
  self.tasks = {}
  self.children = {}
  self.requires = {}
end

-- return root task group
return new_group('')
