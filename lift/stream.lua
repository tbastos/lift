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

-- Registers a function to be called once more data is available for reading,
-- after a try_read() or read() call returns false.
-- The call is only made once. Prototype: cb(stream).
function Stream:on_readable(callback) -- consumer, readable
  error('not a readable stream')
end

-- Registers a function to be called whenever data is read from the stream.
-- Prototype: cb(stream, data, err). The end of the stream is signaled
-- with cb(s, nil, nil); or when an error occurs, with cb(s, nil, err).
function Stream:on_data(callback) -- consumer, readable
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

-- Relays all data flowing out of this stream to the given `writable` stream,
-- automatically managing the flow so that the `writable` is not overwhelmed.
-- If `keep_open` is true, the end-of-stream marker (nil) is not relayed when
-- the stream ends normally. Errors are still sent. Returns `writable`.
function Stream:pipe(writable, keep_open) -- consumer, readable
  error('not a readable stream')
end

-- Writes `data` to the underlying system. Call write(nil) to signal the end
-- of the stream, or write(nil, err) to signal an error.
-- Returns whether you should continue writing right now.
function Stream:write(data, err) -- consumer, writable
  error('not a writable stream')
end

-- Registers a function to be called once it is appropriate to begin writing
-- more data to the stream, after a write() call returns false.
-- The call is only made once. Prototype: cb(stream).
function Stream:on_drain(callback) -- consumer, writable
  error('not a writable stream')
end

-- Registers a function to be called once the stream has been fully written
-- and flushed to the underlying resource.
function Stream:on_finish(callback) -- consumer, writable
  error('not a writable stream')
end

-- Suspends the current thread until the stream has been fully written
-- and flushed to the underlying resource.
function Stream:wait_finish() -- consumer, writable
  error('not a writable stream')
end

-- Returns whether the stream has been fully written and flushed to the
-- underlying resource.
function Stream:has_finished() -- consumer, writable
  error('not a writable stream')
end

------------------------------------------------------------------------------
-- Readable stream
------------------------------------------------------------------------------

local Readable = {
  flowing = false,  -- whether the stream is in flowing mode or paused
  waiting = 0,      -- number of drain events the stream is waiting to restart
}
Readable.__index = Readable

function Readable:on_readable(callback)
  self[#self+1] = callback
end

function Readable:on_data(consumer)
  local t = self.consumers
  t[#t+1] = consumer
end

function Readable:on_end(callback)
  local t = self.on_end_cb
  if not t then t = {} ; self.on_end_cb = t end
  t[#t+1] = callback
end

function Readable:wait_end()
  if self:has_ended() then return self end
  local this_future = async_get()
  self:on_end(function() async_resume(this_future) end)
  co_yield()
  return self
end

function Readable:has_ended()
  return self.rbuf == nil
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
      async.call(self[i], self)
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
        self.read_error = err or false
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
    assert(writable, "missing argument 'writable'")
    local function drained()
      local n = self.waiting - 1 ; self.waiting = n
      if n == 0 then self:start() end
    end
    self:on_data(function(self, data, err) -- luacheck: ignore
      if data ~= nil or err ~= nil or not keep_open then
        if not writable:write(data, err) and data ~= nil then
          self.waiting = self.waiting + 1
          writable:on_drain(drained)
          self:stop()
        end
      end
    end)
    self:start()
    return writable
  end)

local function init_readable(self, reader)
  self.reader = reader
  self.rbuf, self.consumers = {}, {}
  return self
end

-- Creates a readable stream that calls reader(stream) when it needs more data
-- from the stream's underlying resource. The `reader` should call push() to
-- feed in data for as long as push() returns true. Once push() returns false,
-- it should stop reading until the next call to `reader`.
local function new_readable(reader, id)
  return setmetatable(init_readable({id = id}, reader), Readable)
end

------------------------------------------------------------------------------
-- Writable stream
------------------------------------------------------------------------------

local Writable = {}
Writable.__index = Writable

Writable.write = diagnostics.trace(
  '[stream] writing to ${self}: ${data} ${err}',
  function(self, data, err)
    return self.request_write(data, err)
  end)

function Writable:on_drain(callback)
  self[#self+1] = callback
end

function Writable:on_finish(callback)
  local t = self.on_finish_cb
  if not t then t = {} ; self.on_finish_cb = t end
  t[#t+1] = callback
end

function Writable:wait_finish()
  if self:has_finished() then return self end
  local this_future = async_get()
  self:on_finish(function() async_resume(this_future) end)
  co_yield()
  return self
end

function Writable:has_finished()
  return self.write_error ~= nil
end

-- send 'on_drain' event
local send_drain = diagnostics.trace('[stream] drained: ${self}',
  function(self)
    for i = 1, #self do
      async.call(self[i], self)
      self[i] = nil
    end
  end)

-- terminate stream and send 'on_finish' event
local shutdown = diagnostics.trace('[stream] finished: ${self}',
  function(self, err)
    self.write_error = err
    local t = self.on_finish_cb
    if not t then return end
    for i = 1, #t do
      t[i](self)
    end
  end)

-- Constructs a writable stream.
local function init_writable(self, writer, write_many)
  local writing, buf, ended_with_err, sent_end
  local function callback(err)
    if buf then
      local chunks = buf ; buf = nil
      send_drain(self)
      return write_many(self, chunks, callback)
    end
    if err then ended_with_err = err end -- overwrite any preexisting error
    if ended_with_err ~= nil then -- stream has ended
      if sent_end then -- ready to shutdown
        return shutdown(self, ended_with_err)
      else -- the end of stream was buffered, we still have to send it
        sent_end = true
        return writer(self, nil, ended_with_err, callback)
      end
    end
    writing = false
  end
  if not write_many then
    write_many = function(self, buf, last_cb) -- luacheck: ignore
      local i = 1
      local function write_next(err)
        if err then return last_cb(err) end
        i = i + 1
        if i <= #buf then
          return writer(self, buf[i], nil, write_next)
        end
        return last_cb()
      end
      return writer(self, buf[i], nil, write_next)
    end
  end
  function self.request_write(data, err)
    assert(ended_with_err == nil, 'cannot write() past the end of the stream')
    if data == nil then -- end of stream
      ended_with_err = err or false
      if writing then return false else sent_end = true end
    elseif writing or buf then -- buffer a data chunk
      if buf == nil then buf = {data} return true end
      local n = #buf ; buf[n+1] = data
      return n < self.high_water
    end
    writing = true
    writer(self, data, err, callback) -- write data or the end of stream
    return (data ~= nil)
  end
  return self
end

-- Creates a writable stream that calls writer(stream, data, err, callback)
-- when it needs to send data to the stream's underlying resource. The writer
-- must call callback(err) when it's done processing the data chunk, and if a
-- non-nil `err` is specified the stream ends with a write error. The end of
-- the stream is signaled with data = nil; and in this case, `err` is false if
-- the stream ended normally, or an error object otherwise. If `write_many` is
-- provided, the stream will call write_many(stream, chunks, callback) when it
-- needs to write many chunks of data, instead of calling `writer` many times.
local function new_writable(writer, write_many, id)
  return setmetatable(init_writable({id = id}, writer, write_many), Writable)
end

------------------------------------------------------------------------------
-- Duplex stream (a stream that is both readable and writable)
------------------------------------------------------------------------------

local Duplex = {}
Duplex.__index = Duplex

local function new_duplex(reader, writer, write_many, id)
  local self = init_readable({id = id}, reader)
  return setmetatable(init_writable(self, writer, write_many), Duplex)
end

------------------------------------------------------------------------------
-- Stream class inheritance
------------------------------------------------------------------------------

local function inherit_from(child, parent)
  for k, v in pairs(parent) do
    if child[k] == nil then
      child[k] = v
    end
  end
end

inherit_from(Duplex, Readable)
inherit_from(Duplex, Writable)
inherit_from(Duplex, Stream)
inherit_from(Readable, Stream)
inherit_from(Writable, Stream)

------------------------------------------------------------------------------
-- Transform stream (duplex stream where the output is derived from the input)
------------------------------------------------------------------------------

local function new_transform(transform, id)
  local function reader(self)
    -- nothing to do here... we must wait for writes
  end
  local function writer(self, data, err, callback)
    -- TODO implement flow control
    transform(self, data, err, callback)
  end
  return new_duplex(reader, writer, nil, id)
end

------------------------------------------------------------------------------
-- Pass-Through stream
------------------------------------------------------------------------------

local function passthrough(self, data, err, callback)
  self:push(data, err)
end

local function new_passthrough()
  return new_transform(passthrough, 'passthrough')
end

------------------------------------------------------------------------------
-- Array Streams (test helpers)
------------------------------------------------------------------------------

local function array_id(t, delay)
  return tostring(t):gsub('table: 0x',
    'array'..(delay and '+' or '')..(delay or '')..'@')
end

-- Creates a stream that reads data from an array. If `delay` is given, the
-- reader works asynchronously, reading a chunk every `delay` milliseconds.
local function from_array(t, delay)
  local i, n, reader = 1, #t
  if delay then -- async reader
    local reading = false
    reader = function(self)
      if reading then return end
      reading = true
      async(function()
        while 1 do
          local data
          if i <= n then
            data, i = t[i], i + 1
          end
          if not self:push(data) then
            reading = false
            return
          end
          async.sleep(delay)
        end
      end)
    end
  else -- sync reader
    reader = function(self)
      repeat
        local more = self:push(t[i])
        i = i + 1
      until i > n or not more
      if i > n then self:push() end
    end
  end
  return new_readable(reader, array_id(t, delay))
end

-- Creates a stream that writes data to an array. If `delay` is given, the
-- writer works asynchronously, writing a chunk every `delay` milliseconds.
local function to_array(t, delay)
  local size = 1
  local function sync_writer(self, data, err, callback)
    if data == nil then return callback(err) end
    t[size] = data
    size = size + 1
    callback()
  end
  local writer = sync_writer
  if delay then -- async writer
    writer = function(self, data, err, callback)
      async(function()
        async.sleep(delay)
        sync_writer(self, data, err, callback)
      end)
    end
  end
  return new_writable(writer, nil, array_id(t, delay))
end

------------------------------------------------------------------------------
-- UV Streams (TCP/UDP sockets and IPC pipes)
------------------------------------------------------------------------------

local uv = require 'luv'
local uv_write, uv_shutdown = uv.write, uv.shutdown
local uv_read_start, uv_read_stop = uv.read_start, uv.read_stop

-- Creates a reader function for an uv stream.
local function create_uv_reader(handle)
  local dest_stream
  local function on_read(err, data)
    if dest_stream:push(data, err) == false then
      dest_stream = 'ended'
      uv_read_stop(handle)
    end
  end
  local function reader(self)
    if not dest_stream then
      dest_stream = self
      uv_read_start(handle, on_read)
    end
  end
  return reader
end

-- Creates writer and write_many functions for an uv stream.
local function create_uv_writers(handle)
  local function writer(self, data, err, callback)
    if err then return callback(err) end
    if data then
      uv_write(handle, data, callback)
    else
      uv_shutdown(handle, callback)
    end
  end
  local function write_many(self, chunks, callback)
    uv_write(handle, chunks, callback)
  end
  return writer, write_many
end

-- Creates a stream that reads strings from an uv stream.
local function from_uv(handle)
  return new_readable(create_uv_reader(handle), tostring(handle))
end

-- Creates a stream that writes strings to an uv stream.
local function to_uv(handle)
  local writer, write_many = create_uv_writers(handle)
  return new_writable(writer, write_many, tostring(handle))
end

-- Creates a duplex stream that reads and writes strings from/to an uv stream.
local function new_duplex_uv(handle)
  local reader = create_uv_reader(handle)
  local writer, write_many = create_uv_writers(handle)
  return new_duplex(reader, writer, write_many, tostring(handle))
end

------------------------------------------------------------------------------
-- Module Table
------------------------------------------------------------------------------

return {
  from_array = from_array,
  from_uv = from_uv,
  new_duplex = new_duplex,
  new_duplex_uv = new_duplex_uv,
  new_passthrough = new_passthrough,
  new_readable = new_readable,
  new_transform = new_transform,
  new_writable = new_writable,
  to_array = to_array,
  to_uv = to_uv,
}
