local task = require 'lift.task'
local async = require 'lift.async'

function task.hello(args) -- not invoked by default
  print('Hello '..tostring(args[1])..'!')
  return nil, args, true
end

function task.brush_teeth()
  async.sleep(2000) -- 2 seconds
  print 'Brushed teeth.'
end

function task.take_shower(how)
  async.sleep(5000) -- 5 seconds
  print('Took a '..tostring(how)..' shower.')
end

function task.groom_myself() -- 5 seconds total
  async.wait_all{task.brush_teeth:async(), task.take_shower:async('cold')}
end

function task.prepare_coffee_machine()
  async.sleep(1000) -- 1 second
  print 'Prepared coffee machine.'
end

function task.make_coffee(num_cups)
  task.prepare_coffee_machine()
  async.sleep(num_cups * 1000) -- 1 second per cup
  print('Made '..tostring(num_cups)..' cups of coffee.')
end

function task.drink_coffee(num_cups)
  if not num_cups then return task.drink_coffee(2) end
  task.make_coffee(num_cups + 1)
  async.sleep(num_cups * 3000) -- 3 seconds per cup
  print('Drank '..tostring(num_cups)..' cups of coffee.')
end

function task.ready_for_the_day()
  task{task.groom_myself, task.drink_coffee}() -- max(5, 10)
  print 'Ready for the day!'
end

function task.default()
  task.ready_for_the_day()
end
