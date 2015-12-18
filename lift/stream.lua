------------------------------------------------------------------------------
-- Streaming API
------------------------------------------------------------------------------
-- Streams are designed to transport data as fast as possible, using as little
-- memory as possible. A stream becomes slower if some connected stream down
-- the network is slower, in order to avoid overwhelming the system with
-- excessive buffering or data loss.
-- Streams in Lift can carry all types of data. Although data at the endpoints
-- may need to be converted to/from string in order to interface with the OS,
-- as far as Lift is concerned the data can be any Lua object, except nil.
-- Lift uses nil to signal the end of a stream. After the nil comes one final
-- value: "err", the error that terminated the stream, which is `false` if the
-- stream ended successfully.
-- For efficiency, streams always transport data in batches (arrays of data).
-- Streams can be in one of three states: still, flowing or dead.
--   1. A stream is *still* if it's buffering data instead of moving it.
--   2. A stream is *flowing* if it's moving data continuously.
--   3. A stream is *dead* if it already ended (with or without errors).

local assert, setmetatable = assert, setmetatable

-- local co_yield = coroutine.yield
-- local async = require 'lift.async'
-- local async_get, async_resume = async._get, async._resume

local HIGH_WATER_MARK = 8 -- number of data chunks to buffer per stream

------------------------------------------------------------------------------
-- Readable stream
------------------------------------------------------------------------------

local Readable = {
  r_hwm = HIGH_WATER_MARK, -- cease to read underlying resource at this level
}
Readable.__index = Readable

-- Registers a function to be called whenever data is read from the stream.
-- Signature: cb(stream, chunks, n). Each call sends an array of data `chunks`
-- with `n` elements. The end of the stream is signaled with cb(s, nil, nil),
-- or in case of errors with cb(s, nil, err).
function Readable:on_read(consumer) -- for consumers
  self[#self+1] = consumer
end

-- Sends all data in the read buffer to consumers.
local function flush_read_buffer(self)
  local buf, n = self.r_buf, self.r_buf_n
  local dead, err = (buf[n] == nil)
  if dead then err = buf[n+1] ; n = n - 1 end
  if n > 0 then -- send chunks
    for i = 1, #self do
      self[i](self, buf, n)
    end
  end
  if dead then -- send end-of-stream signal
    self.state = 'dead'
    for i = 1, #self do
      self[i](self, nil, err)
    end
  end
  self.r_buf_n = 0 -- empty buffer
end

-- Switches the stream into flowing mode.
function Readable:start() -- for consumers
  local state = self.state
  if state == 'dead' then
    error('cannot start() a dead stream', 2)
  elseif state == 'still' then
    self.state = 'flowing'
    flush_read_buffer(self)
    self:read_more()
  end
end

-- Switches out of flowing mode. Any data read will remain in the read buffer.
function Readable:stop() -- for consumers
  local state = self.state
  if state == 'dead' then
    error('cannot stop() a dead stream', 2)
  elseif state == 'flowing' then
    self.state = 'still'
  end
end

-- Adds `data` to the queue for subsequent stream processors to consume.
-- Call push(nil) to signal the end of the stream, or push(nil, err) to signal
-- an error. No further calls to push() are allowed after that.
function Readable:push(data, err) -- for implementers
  local buf, n = self.r_buf, self.r_buf_n
  n = n + 1
  self.r_buf_n = n
  buf[n] = data
  if err then
    if data ~= nil then error('data must be nil to push() an error', 2) end
    buf[n+1] = err
  elseif data == nil then
    buf[n+1] = false -- stream ended successfully
  end
  return n < self.r_hwm
end

-- Returns the next chunk of data, or nil if the stream is dead. Raises any
-- error pushed into the stream. This method cannot be called in flowing mode.
function Readable:read() -- for consumers
  local state = self.state
  if state == 'dead' then
    return nil
  elseif state == 'flowing' then
    error('cannot call read() while stream is flowing', 2)
  end
  local buf, n = self.r_buf
  ::try_again::
  n = self.r_buf_n
  if n > 0 then
    -- pop the next chunk
    local data = buf[1]
    for i = 2, n do buf[i-1] = buf[i] end
    self.r_buf_n = n - 1
    -- is this the end?
    if data == nil then
      self.state = 'dead'
      local err = buf[2]
      if err then error(err, 2) end
    end
    return data
  end
  -- buffer is empty, read some more data
  self:read_more()
  -- n = co_yield() -- wait for the next push()
  goto try_again
end

-- Makes the given writable stream receive all data flowing out of this
-- readable stream, automatically managing the flow so that the writable
-- is not overwhelmed by a fast readable stream. If `keep_alive` is true, the
-- end-of-stream marker (nil) is not sent to the writable, so it remains alive.
-- Returns the writable stream, so you can set up pipe chains.
function Readable:pipe(writable, keep_open) -- for consumers
  return writable
end

-- Removes the hooks set up for a previous pipe() call.
-- If `writable` is not specified, all pipes are removed.
-- If `writable` is specified but no pipe is set up for it, this is a no-op.
function Readable:unpipe(writable) -- for consumers
  -- body
end

-- Creates a readable stream that calls `read_more` when it needs more data
-- from the underlying resource. The implementation should feed in data by
-- calling push() repeatedly, for as long as push() returns true. When push()
-- returns false, it should stop reading until the next call to `read_more`.
-- The call to `read_more` should not block nor yield.
local function new_readable(read_more) -- for implementers
  return setmetatable({read_more = read_more, state = 'still',
    r_buf = {}, r_buf_n = 0}, Readable)
end

-- Creates a stream that reads data from a list (for tests).
local function from_list(list) -- for testers
  local i, n = 1, #list
  return new_readable(function(stream)
      repeat
        local wants_more = stream:push(list[i])
        i = i + 1
      until i > n or not wants_more
      if i > n then stream:push() end
    end)
end

------------------------------------------------------------------------------
-- Writable stream
------------------------------------------------------------------------------

local Writable = {
  w_hwm = HIGH_WATER_MARK, -- level when write() starts returning false
}
Writable.__index = Writable

-- Forces buffering of all writes until next uncork() or the end of stream.
function Writable:cork() -- for implementers and consumers
  -- body
end

-- local function flush_write_buffer(self)
--   -- body
-- end

-- Flushes all data buffered since last cork() call.
function Writable:uncork() -- for implementers and consumers
  -- body
end

-- Writes `data` to the underlying system. Call write(nil) to signal the end
-- of the stream, or write(nil, err) to signal an error.
-- Returns whether you should continue writing right now.
function Writable:write(data, err) -- for consumers
  local state = self.state
  if state == 'dead' then
    error('cannot write() to a dead stream', 2 )
  end
  local dead = (data == nil or err)
  local buf, n, hwm = self.w_buf, self.w_buf_n, self.w_hwm
  -- add data to the buffer
  if not dead then
    n = n + 1
    buf[n] = data
  end
  -- flush write buffer if it's full or the stream ended
  if n >= hwm or dead then
    self:writer(buf, n)
    n = 0
  end
  -- signal the end of the stream
  if dead then
    assert(data == nil, 'data must be nil when pushing an error')
    self:writer(nil, err)
  end
  self.w_buf_n = n
  return true
end

-- Creates a writable stream that calls `writer` when it needs to send data to
-- the underlying resource. Each call to writer(chunks, n) sends an array of
-- data `chunks` with `n` elements. The end of the stream is signaled with
-- writer(nil), or in case of errors with writer(nil, err).
local function new_writable(writer) -- for implementers
  return setmetatable({writer = writer, state = 'flowing',
      w_buf = {}, w_buf_n = 0}, Writable)
end

-- Creates a stream that writes data to a list (for tests).
local function to_list(list) -- for testers
  local size = 0
  return new_writable(function(stream, chunks, n)
      if not chunks then
        if n then error(n, 2) end
        return
      end
      for i = 1, n do
        list[size+i] = chunks[i]
      end
      size = size + n
    end)
end

------------------------------------------------------------------------------
-- Duplex stream
------------------------------------------------------------------------------


------------------------------------------------------------------------------
-- UV Streams
------------------------------------------------------------------------------

-- local uv = require 'luv'
-- local uv_shutdown = uv.shutdown
-- local uv_read_start, uv_read_stop = uv.read_start, uv.read_stop

return {
  from_list = from_list,
  to_list = to_list,
}
