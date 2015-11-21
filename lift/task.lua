------------------------------------------------------------------------------
-- Task Engine
------------------------------------------------------------------------------

local assert, pairs, tostring, type = assert, pairs, tostring, type
local getmetatable, setmetatable = getmetatable, setmetatable
local str_find = string.find
local tbl_concat, tbl_sort = table.concat, table.sort

-- local diagnostics = require 'lift.diagnostics'
local lstr_format = require('lift.string').format

------------------------------------------------------------------------------
-- CallSet object (callable set of tasks)
------------------------------------------------------------------------------

local CallSet = {}

function CallSet.__call(cs, ...)
  assert(false) -- TODO
end

function CallSet.__tostring(cs)
  local t = {}
  for task, _ in pairs(cs) do
    t[#t+1] = tostring(task)
  end
  tbl_sort(t)
  return 'CallSet('..tbl_concat(t, ' + ')..')'
end

local function new_callset(t1, t2)
  return setmetatable({[t1] = true, [t2] = true}, CallSet)
end

------------------------------------------------------------------------------
-- Task object (memoized function)
------------------------------------------------------------------------------

local Task = {
  name = '?',
}

Task.__index = Task

function Task.__call(task, arg, extra)
  if task.res[arg or 1] then return end
  -- check if the task was called correctly
  local group = task.group
  if arg == group then
    error('tasks must be called as .functions() not :methods()', 2)
  end
  if extra ~= nil then error('tasks can only take one argument', 2) end
  -- call the function and save the results
  task.f(group, arg)
  task.res[arg or 1] = true
end

function Task.__add(a, b)
  local ma, mb = getmetatable(a), getmetatable(b)
  if ma == Task and mb == Task then
    return new_callset(a, b)
  elseif mb == Task then
    assert(ma == CallSet)
  else
    assert(mb == CallSet)
    a, b = b, a
  end
  a[b] = true
  return a
end

function Task.__tostring(task)
  return tostring(task.group)..':'..task.name
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

function Group.__tostring(group)
  local parent = group.parent
  if not parent then return group.name end
  if not parent.parent then return group.name end
  return tostring(parent)..'.'..group.name
end

function Group.__index(t, k)
  return t.tasks[k] or Group[k]
end

function Group.__newindex(t, k, v)
  t.tasks[k] = new_task(t, k, v)
end

function Group:group(name)
  validate_name(name)
  local child, list = new_group(name, self), self.children
  list[#list+1] = child
  return child
end

function Group:reset(args)
  self.tasks = {}
  self.children = {}
  self.requires = {}
end

------------------------------------------------------------------------------
-- Execute a DAG of groups in topological order (i.e. resolving dependencies)
------------------------------------------------------------------------------

--[[
local function toposort(res, marks, node)
  local mark = marks[node]
  if mark == 'done' then return end
  if mark == 'cycle' then
    local cycle = {}
    for i = 1, #marks do
      if marks[i] == node then
        for j = i, #marks do cycle[#cycle + 1] = marks[j].name end
        cycle[#cycle + 1] = node.name
        break
      end
    end
    diagnostics.report("fatal: group graph contains a cycle: ${1}",
        "'" .. table.concat(cycle, "' -> '") .. "'")
  else
    new_group(node)
    marks[node] = 'cycle'
    marks[#marks + 1] = node
    for i, n in ipairs(node.requires) do toposort(res, marks, n) end
    marks[#marks] = nil
    marks[node] = 'done'
    res[#res + 1] = node
  end
end

-- invokes group[task](group, ...) on the whole DAG, in topological order
local function execute(root_group, action, ...)
  assert(#Group.requires == 0, 'the default Group.requires was modified')
  local list = {} toposort(list, {}, root_group)
  for i, group in ipairs(list) do
    local f = group[action]
    if f then
      f(group, ...)
      diagnostics.fail_if_error()
    else
      diagnostics.report("fatal: group '${1}' does not support action '${2}'",
        group.name, tostring(action))
    end
  end
end
]]

-- return root task group
return new_group('')
