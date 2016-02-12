describe('lift.stream', function()

  local su = require 'spec.util'
  local stream = require 'lift.stream'

  local co_yield = coroutine.yield
  local async = require 'lift.async'
  local async_get, async_resume = async._get, async._resume

  describe("readable stream", function()
    it("can be read from synchronously", su.async(function()
      local t = {} ; for i = 1, 20 do t[i] = i end
      local s = stream.from_array(t)
      for i = 1, 20 do
        assert.equal(i, s:try_read())
      end
    end))
    it("can be read from asynchronously", su.async(function()
      local t = {} ; for i = 1, 20 do t[i] = i end
      local s = stream.from_array(t, 2)
      assert.Nil(s:try_read())
      async.sleep(20)
      for i = 1, 20 do
        assert.equal(i, s:read())
      end
    end))
    it("can be piped to another (writable) stream", su.async(function()
      local in1 = {'str', 3.14, {x = 1}, true, false}
      local in2 = {1, 2, 3}
      local in3 = {4, 5, 6}
      local out = {}
      local to_out = stream.to_array(out)
      local from_in1 = stream.from_array(in1) -- sync
      from_in1:pipe(to_out, true) -- don't send end to to_out
      assert.same(in1, out)
      assert.False(to_out:has_finished())
      local from_in2 = stream.from_array(in2, 10) -- async
      from_in2:pipe(to_out) -- send end to to_out (default)
      from_in2:wait_end()
      assert.True(to_out:has_finished())
      assert.not_same(in1, out)
      local expected = {'str', 3.14, {x = 1}, true, false, 1, 2, 3}
      assert.same(expected, out)
      assert.error(function() stream.from_array(in3):pipe(to_out) end,
        'cannot write() past the end of the stream')
      assert.same(expected, out)
    end))
  end)

  describe("writable stream", function()
    it("can be written to", function()
      local list = {}
      local s = stream.to_array(list)
      local n = s.high_water * 2 + 3
      for i = 1, n do
        s:write(i)
      end
      s:write(nil)
      for i = 1, n do
        assert.equal(i, list[i])
      end
    end)
    it("implements flow control", su.async(function()
      local n, input, out1, out2 = 20, {}, {}, {}
      for i = 1, n do input[i] = i*i end
      local fast_in = stream.from_array(input, 1)
      local slow_out = stream.to_array(out1, 10)   -- 10x slower
      local slower_out = stream.to_array(out2, 30) -- 30x slower
      fast_in:pipe(slow_out)
      fast_in:pipe(slower_out) -- the slowest stream sets the pace
      fast_in:wait_end()
      assert.not_same(input, out1)
      assert.not_same(out1, out2)
      slow_out:wait_finish()
      assert.same(input, out1)
      assert.not_same(out1, out2)
      slower_out:wait_finish()
      assert.same(input, out1)
      assert.same(out1, out2)
    end))
  end)

  describe("passthrough stream", function()
    local input = {'str', 3.14, {x = 1}, true, false}
    for i = 1, 20 do input[#input+1] = i end

    it("forwards all data (sync)", su.async(function()
      local out = {}
      local to_out = stream.to_array(out)
      local from_in = stream.from_array(input)
      local pass1 = stream.new_passthrough()
      local pass2 = stream.new_passthrough()
      from_in:pipe(pass1):pipe(pass2):pipe(to_out):wait_finish()
      assert.same(input, out)
    end))

    it("forwards all data (async, slow input)", su.async(function()
      local out = {}
      local to_out = stream.to_array(out)
      local from_in = stream.from_array(input, 20) -- slow input
      local pass1 = stream.new_passthrough()
      local pass2 = stream.new_passthrough()
      from_in:pipe(pass1):pipe(pass2):pipe(to_out):wait_finish()
      assert.same(input, out)
    end))

    it("forwards all data (async, slow output)", su.async(function()
      local out = {}
      local to_out = stream.to_array(out, 20) -- slow output
      local from_in = stream.from_array(input)
      local pass1 = stream.new_passthrough()
      local pass2 = stream.new_passthrough()
      from_in:pipe(pass1):pipe(pass2):pipe(to_out):wait_finish()
      assert.same(input, out)
    end))

  end)

  describe("uv streams", function()
    local uv = require 'luv'

    -- use a TCP echo server to test uv streams
    local function create_server(host, port, on_connection)
      local server = uv.new_tcp()
      uv.tcp_bind(server, host, port)
      uv.listen(server, 128, function(err)
        assert(not err, err)
        local client = uv.new_tcp()
        uv.accept(server, client)
        on_connection(client)
      end)
      return server
    end
    local function create_echo_server()
      local server = create_server('127.0.0.1', 0, function(client)
        uv.read_start(client, function(err, chunk)
          assert(not err, err)
          if chunk then -- echo anything received
            uv.write(client, chunk)
          else -- when the stream ends, close the socket
            uv.close(client)
          end
        end)
      end)
      return uv.tcp_getsockname(server)
    end
    local function new_echo_stream(server_addr)
      local client = uv.new_tcp()
      local this_future = async_get()
      uv.tcp_connect(client, "127.0.0.1", server_addr.port, function(err)
        assert(not err, err)
        async_resume(this_future)
      end)
      co_yield()
      return client
    end

    it("can be written to and read from synchronously", su.async(function()
      local server_addr = create_echo_server()
      local echo = new_echo_stream(server_addr)
      local to_uv = stream.to_uv(echo)
      local from_uv = stream.from_uv(echo)
      to_uv:write('Hello one') -- writes are async
      to_uv:write('Hello two')
      to_uv:write()
      assert.equal('Hello oneHello two', from_uv:read()) -- read() is sync
      assert.Nil(from_uv:read())
    end))

    it("can be piped to and from simplex streams", su.async(function()
      local server_addr = create_echo_server()
      local echo = new_echo_stream(server_addr)
      local to_uv = stream.to_uv(echo)
      local from_uv = stream.from_uv(echo)
      local in1 = {'One', 'Two', 'Three'}
      local in2 = {'Four', 'Five'}
      local out = {} -- everything is written here
      stream.from_array(in1):pipe(to_uv, true)
      from_uv:pipe(stream.to_array(out), true)
      async.sleep(20) -- wait for the message to be echoed by the TCP stream
      async.sleep(20) -- safety margin
      assert.equal('OneTwoThree', table.concat(out))
      stream.from_array(in2):pipe(to_uv)
      from_uv:wait_end()
      assert.equal('OneTwoThreeFourFive', table.concat(out))
    end))

    it("can be piped to/from a chain of duplex streams", su.async(function()
      local server_addr = create_echo_server()
      local one = stream.new_duplex_uv(new_echo_stream(server_addr))
      local two = stream.new_duplex_uv(new_echo_stream(server_addr))
      local three = stream.new_duplex_uv(new_echo_stream(server_addr))
      one:pipe(two):pipe(three)
      one:write('Hello from one')
      assert.equal('Hello from one', three:read())
      two:write('Hello from two')
      assert.equal('Hello from two', three:read())
      one:write()
      assert.Nil(three:read())
      assert.True(two:has_finished())
    end))

  end)

end)
