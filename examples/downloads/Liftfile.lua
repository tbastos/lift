-- Task 'default' downloads two files concurrently
-- Task 'clean' deletes the downloaded files

local fs = require 'lift.fs'
local task = require 'lift.task'
local config = require 'lift.config'
local request = require 'lift.request'

local function download(file_url)
  print('Downloading '..file_url)
  local filename = file_url:match('/([^/]+)$')
  request(file_url):pipe(fs.write_to(filename)):wait_finish()
  return filename
end

function task.greet() -- executed once, despite multiple calls
  print('Hello '..(config.USER or 'unknown')..'!')
end

function task.download_lua()
  task.greet()
  print('Saved '..download('http://www.lua.org/ftp/lua-5.3.2.tar.gz'))
end

function task.download_luarocks()
  task.greet()
  print('Saved '..download('https://github.com/keplerproject/luarocks/archive/v2.3.0.tar.gz'))
end

function task.default()
  task.greet()
  task{task.download_lua, task.download_luarocks}() -- these tasks run in parallel
  print('Done!')
end

function task.clean()
  for path in fs.glob('*.tar.gz') do
    print('Deleting '..path)
    fs.unlink(path)
  end
end

