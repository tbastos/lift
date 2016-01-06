------------------------------------------------------------------------------
-- Default Command-Line Interface
------------------------------------------------------------------------------

local color = require 'lift.color'
local config = require 'lift.config'
local diagnostics = require 'lift.diagnostics'

local app = ...

-- hide options --help and --version
app.options.help.hidden = true
app.options.version.hidden = true

app:flag 'color'
  :desc('--color=off', 'Disable colorized output')
  :action(function(option, value) color.set_enabled(value) end)

local quiet = app:flag 'quiet'
  :desc('--quiet', 'Suppress messages (prints warnings and errors)')
  :action(function(option, value)
      diagnostics.levels.remark = value and 'ignored' or 'remark'
    end)

app:flag 'silent'
  :desc('--silent', 'Suppress messages (prints errors)')
  :action(function(option, value)
      quiet(value) -- implies -quiet
      diagnostics.levels.remark = value and 'ignored' or 'remark'
    end)

app:flag 'trace'
  :desc('--trace', 'Enable debug tracing')
  :action(function(option, value) diagnostics.set_tracing(value) end)

------------------------------------------------------------------------------
-- If config 'gc' is set, toggle garbage collection
------------------------------------------------------------------------------

local gc = config:get_bool'gc'
if gc ~= nil then
  collectgarbage(gc and 'restart' or 'stop')
  diagnostics.report('remark: Garbage collection is ${1}',
    gc and 'enabled' or 'disabled')
end

