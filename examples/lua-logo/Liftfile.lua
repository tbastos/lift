local los = require 'lift.os'
local task = require 'lift.task'
local config = require 'lift.config'
local stream = require 'lift.stream'
local request = require 'lift.request'

-- Returns the contents of an URL
local function fetch(url)
  local buf = {}
  request(url):pipe(stream.to_array(buf)):wait_finish()
  return table.concat(buf)
end

-- Returns contents of 'lua-logo-label.ps' patched with a new label
local function get_logo_postscript(label)
  local ps = fetch('http://www.lua.org/images/lua-logo-label.ps')
  ps = ps:gsub('(powered by)', label)
  return ps
end

-- Creates SVG file by converting 'lua-logo-label.ps' from PostScript
function task.generate_logo()
  local label = config.label or 'Lift'
  local postscript = get_logo_postscript(label)
  -- use the 'convert' tool to convert PostScript to SVG
  -- requires ImageMagick http://www.imagemagick.org/
  local convert_program = assert(los.find_program('convert'))
  local proc = los.spawn{file = convert_program, 'ps:-', 'logo.svg',
    stdout = 'inherit', stderr = 'inherit'}
  proc:write(postscript) -- writes to proc's stdin
  proc:write() -- sends EOF to proc's stdin
  proc:wait() -- wait for 'convert' to finish (optional)
  print("Generated logo.svg with label "..label)
end

task.default = task.generate_logo
