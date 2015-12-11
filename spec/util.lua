------------------------------------------------------------------------------
-- Helper functions for writing tests
------------------------------------------------------------------------------

local async = require 'lift.async'

-- Make it() function run in an async thread.
local function async_it_function(f)
  return function()
    local future = async(f)
    async.run()
    future:check_error()
    async.check_errors()
  end
end

return {
  async = async_it_function,
}
