local task = require 'lift.task'

function task.passthrough(...)
  return ...
end

function task.default()
  return task.passthrough(42)
end
