------------------------------------------------------------------------------
-- Simplified HTTP request client
------------------------------------------------------------------------------
-- Current implementation assumes the `curl` executable is in the ${PATH}.
-- Inspired by https://github.com/request/request

local assert = assert
local fs = require 'lift.fs'
local stream = require 'lift.stream'

local os = require 'lift.os'
local spawn = os.spawn

-- HTTP(S) GET request.
local curl_program = assert(fs.glob('${PATH}/curl')())
local function noop() end
local function get(url)
  if url:sub(1, 1) == '-' then error('malformed URL', 2) end
  local cp = assert(spawn{file = curl_program, '-sS', '-L', url, stdin = 'ignore'})
  local s = stream.new_readable(noop, 'request.get('..url..')')
  local e -- gathers any error received via either stderr or stdout
  local waiting = 2
  local so, se = cp.stdout, cp.stderr
  so:on_data(function(_, data, err)
    if data == nil then
      waiting = waiting - 1
      if waiting == 0 then
        s:push(nil, err or e)
      else
        e = err
      end
    else
      s:push(data)
    end
  end)
  local err_msg = ''
  se:on_data(function(_, data, err)
    if data == nil then
      if err_msg ~= '' then e = err_msg end
      waiting = waiting - 1
      if waiting == 0 then
        s:push(nil, err or e)
      end
    else
      err_msg = err_msg .. data
    end
  end)
  so:start()
  se:start()
  return s
end

------------------------------------------------------------------------------
-- Module Table/Functor
------------------------------------------------------------------------------

return setmetatable({
  get = get,
}, {__call = function(M, ...) -- calling the module == calling get()
  return get(...)
end})
