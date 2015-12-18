describe('lift.os', function()

  local os = require 'lift.os'
  local async = require 'lift.async'
  local su = require 'spec.util'

  it('offers sh() to execute a shell command', su.async(function()
    local out, err = assert(os.sh'echo Hello world!')
    assert.equal('Hello world!\n', out)
    assert.equal('', err)

    out, err = assert(os.sh[[lua -e "io.stderr:write'Hello from stderr'"]])
    assert.equal('', out)
    assert.equal('Hello from stderr', err)

    out, err = os.sh'invalid_cmd error'
    assert.Nil(out)
    assert.match('command failed .* not found', err)
  end))

  describe("child processes", function()

    it("can be started with spawn()", su.async(function()
      local c = assert(os.spawn{file = 'echo', 'Spawn',
        stdin = 'ignore', stdout = 'ignore', stderr = 'ignore'})
      assert.is_number(c.pid)
      assert.is_nil(c.status)
      assert.is_nil(c.signal)
      async.sleep(100)
      assert.equal(0, c.status, c.signal)
    end))

    it("can be terminated with :kill()", su.async(function()
      local c = assert(os.spawn{file = 'sleep', '3',
        stdin = 'ignore', stdout = 'ignore', stderr = 'ignore'})
      assert.is_number(c.pid)
      assert.is_nil(c.status)
      assert.is_nil(c.signal)
      c:kill()
      async.sleep(100)
      assert.equal(0, c.status)
      assert.equal(15, c.signal) -- sigterm
      assert.error(function() c:kill() end,
        'process:kill() called after process termination')
    end))

    it("can inherit fds from parent and be waited for", su.async(function()
      local c = assert(os.spawn{file = 'echo', '\nHello from child process',
        stdin = 'ignore', stdout = 1, stderr = 2})
      assert.Nil(c.status)
      c:wait()
      assert.equal(0, c.status, c.signal)
    end))

    it("can be waited for with a timeout", su.async(function()
      -- with enough time
      local c = assert(os.spawn{file = 'echo', 'this is fast',
        stdin = 'ignore', stdout = 'ignore', stderr = 'ignore'})
      assert.Nil(c.status)
      local status, signal = c:wait(300)
      assert.equal(0, status, signal)
      -- without enough time
      c = assert(os.spawn{file = 'sleep', '5',
        stdin = 'ignore', stdout = 'ignore', stderr = 'ignore'})
      assert.Nil(c.status)
      status, signal = c:wait(300)
      c:kill()
      assert.False(status)
      assert.equal(signal, 'timed out')
    end))

    it("can be written to (stdin) and read from (stdout and stderr)", su.async(function()
      -- local c = assert(os.spawn{file = 'cat'})
      -- c:write('One')
      -- c.stdin:write('Two')
      -- c:shutdown()
      -- local out = c:read()
      -- assert.equal('One\nTwo\n', out)
      -- local err = c.stderr:read()
      -- assert.equal('', err)
    end))

    it("can be piped to another process", function()
      -- body
    end)

  end)

end)
