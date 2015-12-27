------------------------------------------------------------------------------
-- Streaming API
------------------------------------------------------------------------------
-- Streaming is a technique to process data as fast as possible while using as
-- little memory as possible. Streams employ automatic flow control mechanisms
-- that prevent a fast sender from overwhelming a slow receiver. A stream can
-- transmit all types of data. Although data at the endpoints often need to be
-- converted to/from string in order to interface with the OS, as far as Lift
-- is concerned any non-nil value can be transmitted. Lift reserves nil to
-- signal the end of stream. All ended streams have an "error" value, which
-- is false if the stream ended successfully, or an error object otherwise.

local assert, pairs, setmetatable = assert, pairs, setmetatable
local tostring = tostring
local tremove = table.remove

local diagnostics = require 'lift.diagnostics'

local co_yield = coroutine.yield
local async = require 'lift.async'
local async_get, async_resume = async._get, async._resume

------------------------------------------------------------------------------
-- Stream interface
------------------------------------------------------------------------------

local Stream = {
  high_water = 8,  -- maximum number of data chunks to buffer
}

function Stream:__tostring()
  return self.id or tostring(self.reader or self.writer)
end

-- Registers a function to be called whenever data is read from the stream.
-- Prototype: cb(stream, data, err). The end of the stream is signaled
-- with cb(s, nil, nil); or when an error occurs, with cb(s, nil, err).
function Stream:on_data(callback) -- consumer, readable
  error('not a readable stream')
end

-- Registers a function to be called once data becomes available for reading.
-- Assumes stream is currently drained. Calls only once: cb(stream).
function Stream:on_readable(callback) -- consumer, readable
  error('not a readable stream')
end

-- Registers a function to be called when the end-of-stream marker is read.
function Stream:on_end(callback) -- consumer, readable
  error('not a readable stream')
end

-- Suspends the current thread until the end of stream is read from this stream.
function Stream:wait_end() -- consumer, readable
  error('not a readable stream')
end

-- Returns whether the end of stream has already been read from this stream.
function Stream:has_ended() -- consumer, readable
  error('not a readable stream')
end

-- Switches the stream into flowing mode.
function Stream:start() -- consumer, readable
  error('not a readable stream')
end

-- Switches out of flowing mode. Any data read will remain in the read buffer.
function Stream:stop() -- consumer, readable
  error('not a readable stream')
end

-- Adds `data` to the queue for subsequent stream processors to consume.
-- Call push(nil) to signal the end of the stream, or push(nil, err) to signal
-- an error. No further calls to push() are allowed after that.
function Stream:push(data, err) -- implementer, readable
  error('not a readable stream')
end

-- Returns the next chunk of data, or nil if there's no data available.
-- This method should only be called in paused mode. In flowing mode it's called
-- automatically until the internal buffer is drained.
function Stream:try_read() -- consumer, readable
  error('not a readable stream')
end

-- Returns the next chunk of data, or nil if the stream has ended.
-- Raises any error pushed into the stream. May block to wait for more data.
-- This method should only be called in paused mode. In flowing mode it's called
-- automatically until the internal buffer is drained.
function Stream:read() -- consumer, readable
  error('not a readable stream')
end

-- Makes the `writable` stream receive all data flowing out of this stream,
-- automatically managing the flow so that `writable` is not overwhelmed by
-- a fast readable stream. If `keep_open` is true, the end-of-stream marker
-- (nil) is not sent to `writable` when this stream ends successfully (errors
-- are still sent). Returns `writable`.
function Stream:pipe(writable, keep_open) -- consumer, readable
  error('not a readable stream')
end

-- Removes the hooks set up for a previous pipe() call.
-- If `writable` is not specified, all pipes are removed.
-- If `writable` is specified but no pipe is set up for it, this is a no-op.
function Stream:unpipe(writable) -- consumer, readable
  error('not a readable stream')
end

-- Registers a function to be called once all stream data has been written
-- and flushed to the underlying resource (after the stream's end).
function Stream:on_finish(callback) -- consumer, writable
  error('not a writable stream')
end

-- Suspends the current thread until all stream data has been written
-- and flushed to the underlying resource (after the stream's end).
function Stream:wait_finish() -- consumer, writable
  error('not a writable stream')
end

-- Returns whether all stream data has been written and flushed to the
-- underlying resource (after the stream's end).
function Stream:has_finished() -- consumer, writable
  error('not a writable stream')
end

-- Forces buffering of all writes until next uncork() or the end of stream.
function Stream:cork() -- consumer, writable
  error('not a writable stream')
end

-- Flushes all data buffered since last cork() call.
function Stream:uncork() -- consumer, writable
  error('not a writable stream')
end

-- Writes `data` to the underlying system. Call write(nil) to signal the end
-- of the stream, or write(nil, err) to signal an error.
-- Returns whether you should continue writing right now.
function Stream:write(data, err) -- consumer, writable
  error('not a writable stream')
end

------------------------------------------------------------------------------
-- Readable stream
------------------------------------------------------------------------------

local Readable = {flowing = false}
for k, v in pairs(Stream) do Readable[k] = v end -- inherit from Stream
Readable.__index = Readable

function Readable:on_data(consumer)
  local t = self.consumers
  t[#t+1] = consumer
end

function Readable:on_readable(callback)
  self[#self+1] = callback
end

function Readable:on_end(callback)
  local t = self.on_end_cb
  if not t then t = {} ; self.on_end_cb = t end
  t[#t+1] = callback
end

function Readable:wait_end()
  if self:has_ended() then return end
  local this_future = async_get()
  self:on_end(function() async_resume(this_future) end)
  co_yield()
end

function Readable:has_ended()
  return not self.rbuf
end

local function flow(self)
  repeat
    local data = self:try_read()
  until data == nil
end

Readable.start = diagnostics.trace(
  '[stream] started reading ${self}',
  function(self)
    if not self.flowing then
      self.flowing = true
      flow(self)
    end
  end)

Readable.stop = diagnostics.trace(
  '[stream] stopped reading ${self}',
  function(self)
    self.flowing = false
  end)

-- send 'on_data' event
local send_data = diagnostics.trace('[stream] read from ${self}: ${data} ${err}',
  function(self, data, err)
    for k, cb in pairs(self.consumers) do
      cb(self, data, err)
    end
  end)

-- send 'on_readable' event
local send_readable = diagnostics.trace('[stream] readable: ${self}',
  function(self)
    for i = 1, #self do
      self[i](self)
      self[i] = nil
    end
  end)

-- send 'on_end' event
local send_end = diagnostics.trace('[stream] ended: ${self}',
  function(self)
    self.rbuf = nil -- the end has been reached
    local t = self.on_end_cb
    if not t then return end
    for i = 1, #t do
      t[i](self)
    end
  end)


Readable.push = diagnostics.trace(
  '[stream] pushed to ${self}: ${data} ${err}',
  function(self, data, err)
    assert(self.read_error == nil, 'cannot push() past the end of the stream')
    if self.flowing then -- just send the data now
      send_data(self, data, err)
      if data == nil then
        send_readable(self) -- in flowing mode, only send 'readable' at the end
        send_end(self)
        return false
      else
        return true
      end
    end
    -- buffer the data
    if data == nil then -- this is the end of the stream
      self.read_error = err or false
      send_readable(self)
      return false
    end
    local buf = self.rbuf
    local n = #buf
    buf[n+1] = data
    if n == 0 then -- data just became available
      send_readable(self)
    end
    return (n < self.high_water)
  end)

function Readable:try_read()
  local buf = self.rbuf
  if not buf then return end -- stream has ended & the end was read
  local n = #buf
  if n < 1 then -- buffer is empty
    local err = self.read_error
    if err ~= nil then -- stream has ended, but the end hasn't been read yet
      send_data(self, nil, err)
      send_end(self)
      return nil, err
    end
    self:reader() -- try to read some more
    n = #buf
    if n < 1 then -- reader didn't push anything synchronously
      return
    end
  end
  local data = tremove(buf, 1)
  send_data(self, data)
  return data
end

function Readable:read()
  assert(not self.flowing, 'cannot call read() in flowing mode')
  local data, err = self:try_read()
  if data == nil and err == nil then -- wait for next push()
    if not self.rbuf then return end -- unless the stream has ended
    -- wait for next push()
    local this_future = async_get()
    self:on_readable(function() async_resume(this_future) end)
    co_yield()
    data, err = self:try_read()
  end
  if err then error(err) end
  return data
end

Readable.pipe = diagnostics.trace(
  '[stream] creating pipe from ${self} to ${writable} ${keep_open}',
  function(self, writable, keep_open)
    assert(writable, 'missing writable stream')
    local cb
    if keep_open then
      cb = function(stream, data, err)
        if data ~= nil or err ~= nil then
          writable:write(data, err)
        end
      end
    else
      cb = function(stream, data, err)
        writable:write(data, err)
      end
    end
    self.consumers[writable] = cb
    self:start()
    return writable
  end)

Readable.unpipe = diagnostics.trace(
  '[stream] removing pipe from ${self} to ${writable}',
  function(self, writable)
    local consumers = self.consumers
    if writable then
      consumers[writable] = nil
    else -- unpipe all streams
      for k, v in pairs(consumers) do
        if type(k) ~= 'number' then
          consumers[k] = nil
        end
      end
    end
  end)

-- Creates a readable stream that calls reader(stream) when it needs more data
-- from the stream's underlying resource. The `reader` should call push() to
-- feed in data for as long as push() returns true. Once push() returns false,
-- it should stop reading until the next call to `reader`.
local function new_readable(reader, id) -- for implementers
  return setmetatable({id = id, reader = reader, rbuf = {}, consumers = {}}, Readable)
end

------------------------------------------------------------------------------
-- Writable stream
------------------------------------------------------------------------------

local Writable = {corked = 0}
for k, v in pairs(Stream) do Writable[k] = v end -- inherit from Stream
Writable.__index = Writable

function Writable:on_finish(callback)
  local t = self.on_finish_cb
  if not t then t = {} ; self.on_finish_cb = t end
  t[#t+1] = callback
end

function Writable:wait_finish()
  if self:has_finished() then return end
  local this_future = async_get()
  self:on_finish(function() async_resume(this_future) end)
  co_yield()
end

function Writable:has_finished()
  return not self.wbuf
end

function Writable:shutdown()
  self.wbuf = nil
  local t = self.on_finish_cb
  if not t then return end
  for i = 1, #t do
    t[i](self)
  end
end

function Writable:cork()
  self.corked = self.corked + 1
end

local function clear_buffer(self)
  -- send data chunks
  local buf = self.wbuf
  local n = #buf
  if n > 1 then -- many chunks
    local write_many = self.write_many
    if write_many then -- use write_many if available
      self:write_many(buf)
    else
      for i = 1, n do
        self:writer(buf[i])
      end
    end
  elseif n == 1 then -- one chunk
    self:writer(buf[1])
  end
  -- send end of stream
  local err = self.write_error
  if err ~= nil then self:writer(nil, err) end
end

function Writable:uncork()
  local corked = self.corked
  self.corked = corked - 1
  if corked == 1 then
    clear_buffer(self)
  end
end

Writable.write = diagnostics.trace(
  '[stream] writing to ${self}: ${data} ${err}',
  function(self, data, err)
    assert(self.write_error == nil, 'cannot write() past the end of the stream')
    local wants_more
    if self.corked == 0 then -- uncorked: send data directly to writer
      self:writer(data, err)
      wants_more = true
    elseif data ~= nil then  -- corked: buffer data
      local buf = self.wbuf
      local n = #buf
      buf[n+1] = data
      wants_more = (n < self.high_water)
    end
    if data == nil then -- stream has ended
      self.write_error = err or false
      wants_more = false
    end
    return wants_more
  end)

-- Creates a writable stream that calls writer(stream, data) when it needs to
-- send data to the stream's underlying resource. The end of the stream is
-- signaled with writer(nil), or in case of errors with writer(nil, err).
-- If write_many is provided, the stream will call write_many(stream, chunks)
-- when it needs to write many buffered chunks of data, instead of calling
-- writer(stream, data) many times.
local function new_writable(writer, write_many, id) -- for implementers
  return setmetatable({id = id, writer = writer, write_many = write_many,
      wbuf = {}}, Writable)
end

------------------------------------------------------------------------------
-- Duplex stream
------------------------------------------------------------------------------

local Duplex = {}
for k, v in pairs(Readable) do Duplex[k] = v end -- inherit from Readable
for k, v in pairs(Writable) do Duplex[k] = v end -- inherit from Writable
Duplex.__index = Duplex

------------------------------------------------------------------------------
-- Array Streams (for tests)
------------------------------------------------------------------------------

-- Creates a stream that reads data from an array (for tests).
local function from_array(t)
  local i, n = 1, #t
  return new_readable(function(stream)
      repeat
        local more = stream:push(t[i])
        i = i + 1
      until i > n or not more
      if i > n then stream:push() end
    end, tostring(t))
end

-- Creates a stream that writes data to an array (for tests).
local function to_array(t)
  local size = 1
  return new_writable(function(stream, data, err)
      if data == nil then
        if err then error(err, 2) end
        stream:shutdown()
      else
        t[size] = data
        size = size + 1
      end
    end, nil, tostring(t))
end

------------------------------------------------------------------------------
-- UV Streams (TCP/UDP sockets and IPC pipes)
------------------------------------------------------------------------------

local uv = require 'luv'
local uv_write, uv_shutdown = uv.write, uv.shutdown
local uv_read_start, uv_read_stop = uv.read_start, uv.read_stop

-- Creates a stream that reads strings from an uv stream.
local function from_uv(handle)
  local reading, stream = false
  local function on_read(err, data)
    if stream:push(data, err) == false then
      reading = false
      uv_read_stop(handle)
    end
  end
  local function reader()
    if not reading then
      reading = true
      uv_read_start(handle, on_read)
    end
  end
  stream = new_readable(reader, tostring(handle))
  return stream
end

-- Creates a stream that writes strings to an uv stream.
local function to_uv(handle)
  local function writer(stream, data, err)
    if err then
      error(err)
    elseif data then
      uv_write(handle, data)
    else
      uv_shutdown(handle, function() stream:shutdown() end)
    end
  end
  local function write_many(stream, chunks)
    uv_write(handle, chunks)
  end
  return new_writable(writer, write_many, tostring(handle))
end

------------------------------------------------------------------------------
-- Module Table
------------------------------------------------------------------------------

return {
  new_readable = new_readable,
  new_writable = new_writable,
  from_array = from_array,
  from_uv = from_uv,
  to_array = to_array,
  to_uv = to_uv,
}
