local task = require 'lift.task'
local utils = require 'lift.utils'
local lstring = require 'lift.string'
local ESC = require('lift.color').ESC

local write = io.write
local app = ...

local task_cmd = app:command 'task'
  :desc('task', 'Subcommands to interface with tasks')

-- task run
local run_cmd = task_cmd:command 'run'
  :desc('run [tasks]', 'Run a set of tasks concurrently')
  :epilog("If no task name is given, the 'default' task is run.")

function run_cmd:run()
  local task_set = task{}
  for i, name in ipairs(self.args) do
    task_set[i] = task:get_task(name)
  end
  if #task_set == 0 then
    task_set[1] = task:get_task 'default'
  end
  task_set()
end

-- tast call
local call_cmd = task_cmd:command 'call'
  :desc('call <task> [args]', 'Invoke a task passing a list of arguments')

function call_cmd:run()
  local callee = task:get_task(self:consume 'task')
  local args = self.args
  args[0] = nil
  args.used = nil -- don't complain about unused args
  table.remove(args, 1)
  write(ESC'green', 'Calling ', tostring(callee), lstring.format(args),
    ESC'clear', '\n')
  callee(args)
  local res = callee:get_result_for(args)
  write(ESC'green', 'Task results = ', lstring.format(res), ESC'clear')
end

-- task list
local list_cmd = task_cmd:command 'list'
  :desc('list [pattern]', 'Print tasks that match an optional pattern')

local function list_namespace(ns, pattern)
  local tasks, count = ns.tasks, 0
  for i, name in ipairs(utils.keys_sorted(tasks)) do
    local full_name = tostring(tasks[name])
    if full_name:find(pattern) then -- filter by pattern
      count = count + 1
      local indent = (' '):rep(30 - #full_name)
      write(full_name, indent, ESC'dim', '-- undocumented task', ESC'clear', '\n')
    end
  end
  local nested = ns.nested
  for i, name in ipairs(utils.keys_sorted(nested)) do
    count = count + list_namespace(nested[name], pattern)
  end
  return count
end

function list_cmd:run()
  local pattern = '.'
  if #self.args > 0 then
    pattern = self:consume 'pattern'
  end
  local count = list_namespace(task, pattern)
  local suffix = (pattern == '.' and '' or (" with pattern '"..pattern.."'"))
  write(ESC'dim', '-- Found ', count, ' tasks', suffix, ESC'clear', '\n')
end
