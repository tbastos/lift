------------------------------------------------------------------------------
-- Task Engine
------------------------------------------------------------------------------

local assert, ipairs = assert, ipairs

local diagnostics = require 'lift.diagnostics'

------------------------------------------------------------------------------
-- Task (a named object with methods and dependencies)
------------------------------------------------------------------------------

local Task = {
  name = 'unknown', -- Every task should have a unique name, for debugging.
  requires = {},    -- By default a task has no dependencies.
}
Task.__index = Task

local function makeTask(t) return setmetatable(t, Task) end

------------------------------------------------------------------------------
-- Execute a DAG of tasks in topological order (i.e. resolving dependencies)
------------------------------------------------------------------------------

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
    diagnostics.report("fatal: task graph contains a cycle: ${1}",
        "'" .. table.concat(cycle, "' -> '") .. "'")
  else
    makeTask(node)
    marks[node] = 'cycle'
    marks[#marks + 1] = node
    for i, n in ipairs(node.requires) do toposort(res, marks, n) end
    marks[#marks] = nil
    marks[node] = 'done'
    res[#res + 1] = node
  end
end

-- invokes task[action](task, ...) on the whole DAG, in topological order
local function execute(rootTask, action, ...)
  assert(#Task.requires == 0, 'the default Task.requires was modified')
  local list = {} toposort(list, {}, rootTask)
  for i, task in ipairs(list) do
    local f = task[action]
    if f then
      f(task, ...)
      diagnostics.fail_if_error()
    else
      diagnostics.report("fatal: task '${1}' does not support action '${2}'",
        task.name, tostring(action))
    end
  end
end

------------------------------------------------------------------------------
-- Module Table
------------------------------------------------------------------------------

local M = {
  -- Task Framework
  Task = Task,
  execute = execute,
}

return M
