local task = require 'lift.task'

function task:default(...)
  return 42, ...
end
