------------------------------------------------------------------------------
-- Default Command-Line Interface
------------------------------------------------------------------------------

local color = require 'lift.color'
local diagnostics = require 'lift.diagnostics'

local app = ...

-- hide options --help and --version
app.options.help.hidden = true
app.options.version.hidden = true

-- enable colors by default on supported terminals
color.set_enabled(os.getenv('TERM') or os.getenv('ANSICON'))

app:flag 'color'
  :desc('--color[=off]', 'Toggle colorized output')
  :action(function(option, value) color.set_enabled(value) end)

app:flag 'trace'
  :desc('--trace', 'Enable debug tracing')
  :action(function(option, value) diagnostics.set_tracing(value) end)

