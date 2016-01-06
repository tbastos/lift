expose("lift.async", function()

  local function fa(n) return n end -- keep this at line 3

  local uv = require 'luv'
  local async = require 'lift.async'

  local TOLERANCE = 20 -- time tolerance for timer callbacks
  if os.getenv('CI') then
    TOLERANCE = 50 -- increase tolerance in CI build servers
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

  it("offers call(f, arg) to invoke a function directly from the event loop", function()
    local v = 0 ; local function add(x) v = v + x end
    async.call(add, 2)
    async.call(add, 3)
    assert.equal(0, v)
    async.run()
    assert.equal(5, v)
  end)

  it("forbids the main thread from blocking", function()
    assert.error_match(function() async.sleep(10) end,
      'not in a lift.async coroutine')
  end)

  describe("a future", function()
    it("stores all function .results in a list", function()
      local function fb(arg, extra) return 1, 2, arg, extra end
      local function fc() return nil, 'omg' end
      local a = async(fa, 1337)
      local b = async(fb, 3.14, 'nope')
      local c = async(fc)
      assert.match('async%(function<spec/async_spec.lua:3>, 1337%)', a)
      assert.falsy(a.results)
      assert.falsy(b.results)
      assert.falsy(c.results)
      async.run()
      assert.equal('fulfilled', a.status, b.status, c.status)
      assert.same({1337}, a.results)
      assert.same({1, 2, 3.14}, b.results)
      assert.same({nil, 'omg'}, c.results)
    end)
    it("stores errors in .error", function()
      local f = async(function() error('boom') end)
      assert.falsy(f.error)
      assert.falsy(f.status)
      async.run()
      assert.equal('failed', f.status)
      assert.matches('boom', tostring(f.error))
    end)
    it("propagates errors when .results is accessed", function()
      local f = async(function() error('boom') end)
      assert.falsy(f.error)
      assert.falsy(f.results)
      async.run()
      assert.error_match(function() return f.results end, 'boom')
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
      local t0 = uv.hrtime()
      async.run()
      local elapsed = (uv.hrtime() - t0)/1000000 -- from ns to ms
      assert.near(30, sleep_30.results[1], TOLERANCE)
      assert.near(60, sleep_60.results[1], TOLERANCE)
      assert.near(90, sleep_90.results[1], TOLERANCE)
      assert.near(90, elapsed, TOLERANCE)
      async.check_errors() -- no unchecked errors
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
      assert.error_match(function() return future.results end,
        'future cannot wait for itself')
      -- catching errors
      local function boom() error('booom!') end
      local function wait_boom() return async.wait(async(boom)) end
      local function assert_wait_boom() assert(async.wait(async(boom))) end
      local only_wait, assert_wait = async(wait_boom), async(assert_wait_boom)
      async.run()
      assert.falsy(only_wait.error)
      assert.falsy(only_wait.results[1])
      assert.match('booom!', only_wait.results[2])
      assert.match('booom!', assert_wait.error)
      assert.error_match(function() return assert_wait.results end, 'booom!')
      async.check_errors() -- no unchecked errors
    end)

    it("can wait() for a coroutine with a timeout", function()
      local function short_task() async.sleep(TOLERANCE) return 1 end
      local function long_task() async.sleep(3*TOLERANCE) return 2 end
      local function patient_wait(future) return async.wait(future, 4*TOLERANCE) end
      local function impatient_wait(future) return async.wait(future, 2*TOLERANCE) end
      -- successfully wait for a short task
      local f = async(impatient_wait, async(short_task))
      async.run()
      assert.same({true, {1}}, f.results)
      -- unsuccessfully wait for a long task
      f = async(impatient_wait, async(long_task))
      async.run()
      assert.same({false, 'timed out'}, f.results)
      -- successfully wait for a long task
      f = async(patient_wait, async(long_task))
      async.run()
      assert.same({true, {2}}, f.results)
      async.check_errors() -- no unchecked errors
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
        async.abort()
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
      future = async(function() assert(async.wait_any{a, b}) end)
      async.run()
      assert.equal(b.error, future.error)
      assert.matches('boom', tostring(future.error))
      async.check_errors() -- no unchecked errors
    end)

    it("can wait_all() multiple coroutines to finish", function()
      local function sleep(ms) async.sleep(ms) end
      local n, list = 6, {}
      for i = 1, n do
        list[i] = async(sleep, i * TOLERANCE)
      end
      local function main()
        assert(async.wait_all(list))
        local count = 0 -- fulfilled futures
        for i = 1, n do
          if list[i].results then
            count = count + 1
          end
        end
        return count
      end
      local future = async(main)
      local t0 = uv.hrtime()
      async.run()
      local elapsed  = (uv.hrtime() - t0)/1000000 -- ns to ms
      assert.equal(n, future.results[1])
      assert.near(n * TOLERANCE, elapsed, TOLERANCE)
      -- add some errors to the mix
      local function raise(i)
        async.sleep(i * TOLERANCE)
        error('my error #'..i)
      end
      list[n+1] = async(raise, 1)
      list[n+2] = async(raise, 2)
      future = async(main)
      async.run()
      assert.matches('caught 2 errors.*my error #1.*my error #2',
        tostring(future.error))
      async.check_errors() -- no unchecked errors
    end)

    it("may deadlock", function()
      local a, b
      local function wait_a() async.wait(a) end
      local function wait_b() async.wait(b) end
      a, b = async(wait_b), async(wait_a)
      local c = async(function()
        async.wait(a, 20)
        return a.results and b.results
      end)
      async.run()
      assert.False(c.results[1])
    end)

  end)

  it("keeps track of unchecked errors", function()
    local function boom() error('boom') end
    local a = async(boom, 1)
    local b = async(boom, 2)
    local function unchecked(future) async.wait(a) return a.results end
    async(unchecked, 3)
    async(unchecked, 4)
    async.run()
    local _ = b.error -- checks checked_b
    assert.error_match(function() async.check_errors() end,
      '2 unchecked async errors')
  end)

end)
