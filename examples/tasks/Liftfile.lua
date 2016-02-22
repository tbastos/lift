local task = require 'lift.task'
local async = require 'lift.async'

function task.brush_teeth()
  print 'Brushing teeth...'
  async.sleep(2000) -- 2 seconds
  print 'Finished brushing teeth.'
end

function task.take_shower()
  print 'Taking a shower...'
  async.sleep(3000) -- 3 seconds
  print 'Finished taking a shower.'
end

function task.get_ready() -- takes 5 seconds total
  task.take_shower()
  task.brush_teeth()
  print 'Done!'
end

function task.get_ready_fast() -- takes just 3 seconds
  task{task.take_shower, task.brush_teeth}()
  print 'Done fast!'
end

-- annotate the main tasks
task.get_ready:desc('Take a shower then brush teeth (serial)')
task.get_ready_fast:desc('Brush teeth while taking a shower (parallel)')

task.default = task.get_ready
