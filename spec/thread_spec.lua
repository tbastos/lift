describe("lift.thread", function()

  local uv = require 'lluv'
  local thread = require 'lift.thread'

  it("offers run() to run all scheduled functions to completion", function()
    thread.run()
  end)

  it("offers spawn(f, arg) to schedule a function to run in a coroutine", function()
    local function f_a(arg, extra) return 1, 2, arg, extra end
    local function f_b() return nil, 'omg' end
    local a = thread.spawn(f_a, 1337)
    local b = thread.spawn(f_b)
    assert.matches('lift.thread.Future%(.*, 1337%)', tostring(a))
    assert.falsy(a.results)
    assert.falsy(b.results)
    thread.run()
    assert.same({1, 2, 1337}, a.results)
    assert.same({nil, 'omg'}, b.results)
  end)

  describe("coroutines", function()

    it("can sleep() and resume later", function()
      local function test_sleep(dt) return thread.sleep(dt) end
      local sleep_30 = thread.spawn(test_sleep, 30)
      local sleep_90 = thread.spawn(test_sleep, 90)
      local sleep_60 = thread.spawn(test_sleep, 60)
      local t0 = uv.now()
      thread.run()
      local elapsed = uv.now() - t0
      local tolerance = 25
      assert.near(20, sleep_30.results[1], tolerance)
      assert.near(60, sleep_60.results[1], tolerance)
      assert.near(90, sleep_90.results[1], tolerance)
      assert.near(90, elapsed, tolerance)
      assert.True(sleep_30.results[2] < sleep_60.results[2])
      assert.True(sleep_60.results[2] < sleep_90.results[2])
    end)

    it("can wait() for another coroutine to finish", function()
      local v = 1
      local function add_two() thread.sleep(0) v = v + 2 end
      local function times_two() v = v * 2 end
      local function wait_times_two(future) thread.wait(future) v = v * 2 end
      -- test without wait
      thread.spawn(add_two)
      thread.spawn(times_two)
      thread.run()
      assert.equal(4, v)
      -- test with wait
      v = 1
      thread.spawn(wait_times_two, thread.spawn(add_two))
      thread.run()
      assert.equal(6, v)
    end)

  end)

end)
