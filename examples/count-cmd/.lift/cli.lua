local fs = require 'lift.fs'
local async = require 'lift.async'

-- extend the CLI with a new 'count' command
local app = ... -- app is the root CLI command, which is passed to this script
local count_cmd = app:command 'count'
  :desc('count <ext> [dir]',
    'Count file names ending in ".ext" within [dir] (defaults to current dir)')

count_cmd:flag 'lines' -- count accepts the '--lines' flag
  :desc('--lines', 'Count the number of lines in files')

-- function to count lines by streaming from a file in a thread
local function count_lines_in(filename)
  local count = 0
  local readable = fs.read_from(filename)
  while 1 do
    local data = readable:read() -- sync read
    if not data then break end -- EOF
    local pos = 0
    while 1 do
      pos = data:find('\n', pos + 1, true) -- find next \n in data
      if not pos then break end
      count = count + 1
    end
  end
  return count
end

-- define action for the 'count' command
count_cmd:action(function(cmd)
  local ext = cmd:consume('extension') -- read required ext argument
  if not ext:match('^%w+$') then -- validate the extension name
    return "invalid extension '"..ext.."' (expected a plain word)"
  end
  -- read the optional dir argument, which defaults to CWD
  local dir = #cmd.args > 1 and cmd:consume('dir') or fs.cwd()
  if not fs.is_dir(dir) then return "no such dir "..dir end
  local count_lines = cmd.options.lines.value -- state of --lines flag
  local futures = {} -- only used if we spawn threads to count lines
  -- use glob to find files (note: /**/ ignores dot dirs by default)
  local num_files, vars = 0, {dir = dir, ext = ext}
  for filename in fs.glob('${dir}/**/*.${ext}', vars) do
    num_files = num_files + 1
    if count_lines then -- spawn thread to count lines
      futures[#futures + 1] = async(count_lines_in, filename)
    end
  end
  print('There are '..num_files..' files with extension .'..ext..' in '..dir)
  if count_lines then
    print('Counting number of lines in files...')
    async.wait_all(futures) -- wait for threads to finish
    local num_lines = 0 -- sum line counts returned by each thread
    for i, future in ipairs(futures) do
      num_lines = num_lines + future.results[1]
    end
    print('Total number of lines: '..num_lines)
  end
end)

