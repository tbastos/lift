local task = require 'lift.task'
local path = require 'lift.path'
local util = require 'lift.util'
local write, inspect = io.write, util.inspect
local ESC = require'lift.color'.ESC
local app = ...

local task_cmd = app:command 'task'
  :desc('task', 'Subcommands to interface with tasks')

------------------------------------------------------------------------------
-- Option: --plot file.svg
------------------------------------------------------------------------------

local plot_option = task_cmd:option 'plot'
  :desc('--plot file.svg', 'Use graphviz to plot task dependencies')

local plot_file
function plot_option:matched(filename)
  plot_file = filename
  -- monkey patch Task:async() to track elapsed times
  local now = os.time
  local task_async = task._Task.async
  local function set_dt(future)
    future.dt = now() - future.t0
  end
  function task._Task.async(tsk, ...)
    local future = task_async(tsk, ...)
    if not future.t0 then
      future.t0 = now()
      future:on_ready(set_dt)
    end
    return future
  end
end

local function format_task(future)
  local arg = future.arg
  if arg then
    arg = ' ('..util.inspect(arg)..')'
  else
    arg = ''
  end
  return '<'..tostring(future.task)..arg..'>'
end

local function visit(from, sb)
  if from.visited then return end
  from.visited = true
  local calls = from.calls
  for i = 1, #calls do
    local to = calls[i]
    sb[#sb+1] = format_task(from)
    sb[#sb+1] = ' -> '
    sb[#sb+1] = format_task(to)
    sb[#sb+1] = '[label="  '..to.dt..'s  "];\n'
    visit(to, sb)
  end
end

local function plot_graph()
  if not plot_file then return end
  local sb = {'digraph graphname {\n'}
  local roots = task._get_roots()
  for i = 1, #roots do
    visit(roots[i], sb)
  end
  sb[#sb+1] = '}\n'
  local format = path.ext(plot_file)
  local dot = require'lift.os'.spawn{file = 'dot', '-T'..format,
    '-o', plot_file, stdout = 'inherit', stderr = 'inherit'}
  dot:write(table.concat(sb))
  dot:write()
end

------------------------------------------------------------------------------
-- Command: task run
------------------------------------------------------------------------------

local run_cmd = task_cmd:command 'run'
  :desc('run [tasks]', 'Run a set of tasks concurrently')
  :epilog("If no task name is given, the 'default' task is run.")

function run_cmd:run()
  local tasks = task{}
  for i, name in ipairs(self.args) do
    tasks[i] = task:get_task(name)
  end
  if #tasks == 0 then
    tasks[1] = task:get_task 'default'
  end
  tasks()
  plot_graph()
end

------------------------------------------------------------------------------
-- Command: task call
------------------------------------------------------------------------------

local call_cmd = task_cmd:command 'call'
  :desc('call <task> [args]', 'Invoke a task passing a list of arguments')

function call_cmd:run()
  local callee = task:get_task(self:consume 'task')
  local args = self.args
  args[0] = nil
  args.used = nil -- disable warning about unused args
  table.remove(args, 1)
  write(ESC'green', 'Calling ', tostring(callee), inspect(args),
    ESC'clear', '\n')
  callee(args)
  local res = callee:get_results(args)
  write(ESC'green', 'Task results = ', inspect(res), ESC'clear')
  plot_graph()
end

------------------------------------------------------------------------------
-- Command: task list
------------------------------------------------------------------------------

local list_cmd = task_cmd:command 'list'
  :desc('list [pattern]', 'Print tasks that match an optional pattern')

local function list_namespace(ns, pattern)
  local tasks, count = ns.tasks, 0
  for i, name in ipairs(util.keys_sorted(tasks)) do
    local full_name = tostring(tasks[name])
    if full_name:find(pattern) then -- filter by pattern
      count = count + 1
      local indent = (' '):rep(30 - #full_name)
      write(full_name, indent, ESC'dim', '-- undocumented task', ESC'clear', '\n')
    end
  end
  local nested = ns.nested
  for i, name in ipairs(util.keys_sorted(nested)) do
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
