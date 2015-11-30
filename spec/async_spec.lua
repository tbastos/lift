describe("lift.async", function()

  local uv = require 'lluv'
  local async = require 'lift.async'

  local TOLERANCE = 20 -- time tolerance for timer callbacks
  if os.getenv('CI') then
    TOLERANCE = 40 -- increase tolerance in CI build servers
  end

  it("offers run() to run all async functions to completion", function()
    async.run()
  end)

  it("offers async(f, arg) to schedule a function to run in a coroutine", function()
    local v = 0
    async(function(x, extra) v = v + x assert(extra == nil) end, 3, 'nope')
    async(function() v = v + 2 end)
    assert.equal(0, v)
    async.run()
    assert.equal(5, v)
  end)

  it("forbids the main thread from blocking", function()
    assert.error_matches(function() async.sleep(10) end, 
      'not in a lift.async coroutine')
  end)

  describe("a future", function()
    it("stores all function .results in a list", function()
      local function f_a(arg, extra) return 1, 2, arg, extra end
      local function f_b() return nil, 'omg' end
      local a = async(f_a, 1337, 'nope')
      local b = async(f_b)
      assert.matches('lift.async.Future%(.*, 1337%)', tostring(a))
      assert.falsy(a.results)
      assert.falsy(b.results)
      assert.False(a.ready)
      assert.False(b.ready)
      async.run()
      assert.True(a.ready)
      assert.True(b.ready)
      assert.same({1, 2, 1337}, a.results)
      assert.same({nil, 'omg'}, b.results)
    end)
    it("stores errors in .error", function()
      local f = async(function() error('boom') end)
      assert.falsy(f.error)
      assert.False(f.ready)
      async.run()
      assert.True(f.ready)
      assert.matches('boom', tostring(f.error))
    end)
    it("propagates errors when .results is accessed", function()
      local f = async(function() error('boom') end)
      assert.falsy(f.error)
      assert.falsy(f.results)
      async.run()
      assert.error_matches(function() return f.results end, 'boom')
    end)
    it("supports callbacks for when it becomes ready", function()
      local v = 0
      local function cb1() v = v + 1 end
      local function cb2() v = v + 2 end
      local f = async(function() end)
      f:on_ready(cb1)
      f:on_ready(cb2)
      async.run()
      assert.equal(3, v)
    end)
  end)

  describe("a coroutine", function()

    it("can sleep() and resume later", function()
      local function test_sleep(dt) return async.sleep(dt) end
      local sleep_30 = async(test_sleep, 30)
      local sleep_90 = async(test_sleep, 90)
      local sleep_60 = async(test_sleep, 60)
      local t0 = uv.now()
      async.run()
      local elapsed = uv.now() - t0
      assert.near(20, sleep_30.results[1], TOLERANCE)
      assert.near(60, sleep_60.results[1], TOLERANCE)
      assert.near(90, sleep_90.results[1], TOLERANCE)
      assert.near(90, elapsed, TOLERANCE)
    end)

    it("can wait() for another coroutine to finish", function()
      local v = 1
      local function add_two() async.sleep(0) v = v + 2 end
      local function times_two() v = v * 2 end
      local function wait_times_two(future) async.wait(future) v = v * 2 end
      -- without wait()
      async(add_two)
      async(times_two)
      async.run()
      assert.equal(4, v)
      -- with wait()
      v = 1
      async(wait_times_two, async(add_two))
      async.run()
      assert.equal(6, v)
      -- waiting for itself?
      local future
      local function wait_self() return async.wait(future) end
      future = async(wait_self)
      async.run()
      assert.error_matches(function() return future.results end,
        'future cannot wait for itself')
      -- error propagation
      local function boom() error('booom!') end
      local function wait_boom() async.wait(async(boom)) end
      future = async(wait_boom)
      async.run()
      assert.matches('booom!', tostring(future.error))
    end)

    it("can wait() for a coroutine with a timeout", function()
      local function short_task() async.sleep(20) return 1 end
      local function long_task() async.sleep(60) return 2 end
      local function patient_wait(future) return async.wait(future, 80) end
      local function impatient_wait(future) return async.wait(future, 40) end
      -- successfully wait for a short task
      local f = async(impatient_wait, async(short_task))
      async.run()
      assert.True(f.results[1])
      assert.same({1}, f.results[2])
      -- unsuccessfully wait for a long task
      f = async(impatient_wait, async(long_task))
      async.run()
      assert.False(f.results[1])
      -- successfully wait for a long task
      f = async(patient_wait, async(long_task))
      async.run()
      assert.True(f.results[1])
      assert.same({2}, f.results[2])
    end)

    it("can wait_any() one of multiple coroutines to finish", function()
      local function sleep(ms) async.sleep(ms) end
      local n, list = 50, {}
      for i = 1, n do
        list[i] = async(sleep, (n - i + 1) * TOLERANCE)
      end
      local function wait_first()
        local first = async.wait_any(list)
        local count = 0 -- fulfilled futures
        for i = 1, n do
          if list[i].results then
            count = count + 1
          end
        end
        async.stop()
        return first, count
      end
      local future = async(wait_first)
      local t0 = uv.now()
      async.run()
      local elapsed  = uv.now() - t0
      assert.equal(list[n], future.results[1]) -- last future is fastest
      assert.equal(1, future.results[2])
      assert.near(TOLERANCE, elapsed, TOLERANCE)
      -- waiting again should return the same future
      future = async(function() return async.wait_any(list) end)
      async.run()
      assert.equal(list[n], future.results[1])
      -- wait for an error
      local a = async(sleep, 1)
      local b = async(function() error('boom') end)
      future = async(function() async.wait_any{a, b} end)
      async.run()
      assert.equal(b.error, future.error)
      assert.matches('boom', tostring(future.error))
    end)

    it("can wait_all() multiple coroutines to finish", function()
      local function sleep(ms) async.sleep(ms) end
      local n, list = 6, {}
      for i = 1, n do
        list[i] = async(sleep, i * TOLERANCE)
      end
      local function main()
        async.wait_all(list)
        local count = 0 -- fulfilled futures
        for i = 1, n do
          if list[i].results then
            count = count + 1
          end
        end
        return count
      end
      local future = async(main)
      local t0 = uv.now()
      async.run()
      local elapsed  = uv.now() - t0
      assert.equal(n, future.results[1])
      assert.near(n * TOLERANCE, elapsed, TOLERANCE)
      -- add some errors to the mix
      local function raise(i)
        async.sleep(i * TOLERANCE)
        error('error #'..i)
      end
      list[n+1] = async(raise, 1)
      list[n+2] = async(raise, 2)
      future = async(main)
      async.run()
      assert.matches('caught 2 errors.*error #1.*error #2',
        tostring(future.error))
    end)

  end)

end)
