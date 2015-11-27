describe("lift.thread", function()

  local uv = require 'lluv'
  local thread = require 'lift.thread'

  local TOLERANCE = 20 -- time tolerance for timer callbacks
  if os.getenv('CI') then
    TOLERANCE = 40 -- increase tolerance in CI build servers
  end

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
      assert.near(20, sleep_30.results[1], TOLERANCE)
      assert.near(60, sleep_60.results[1], TOLERANCE)
      assert.near(90, sleep_90.results[1], TOLERANCE)
      assert.near(90, elapsed, TOLERANCE)
      assert.True(sleep_30.results[2] < sleep_60.results[2])
      assert.True(sleep_60.results[2] < sleep_90.results[2])
    end)

    it("can wait() for another coroutine to finish", function()
      local v = 1
      local function add_two() thread.sleep(0) v = v + 2 end
      local function times_two() v = v * 2 end
      local function wait_times_two(future) thread.wait(future) v = v * 2 end
      -- without wait
      thread.spawn(add_two)
      thread.spawn(times_two)
      thread.run()
      assert.equal(4, v)
      -- with wait
      v = 1
      thread.spawn(wait_times_two, thread.spawn(add_two))
      thread.run()
      assert.equal(6, v)
      -- waiting for itself?
      local future
      local function wait_self() return thread.wait(future) end
      future = thread.spawn(wait_self)
      thread.run()
      assert.equal(true, future.results[1])
    end)

    it("can wait() for a coroutine with a timeout", function()
      local function short_task() thread.sleep(20) end
      local function long_task() thread.sleep(60) end
      local function patient_wait(future) return thread.wait(future, 80) end
      local function impatient_wait(future) return thread.wait(future, 40) end
      -- successfully wait for a short task
      local f = thread.spawn(impatient_wait, thread.spawn(short_task))
      thread.run()
      assert.True(f.results[1])
      -- unsuccessfully wait for a long task
      f = thread.spawn(impatient_wait, thread.spawn(long_task))
      thread.run()
      assert.False(f.results[1])
      -- successfully wait for a long task
      f = thread.spawn(patient_wait, thread.spawn(long_task))
      thread.run()
      assert.True(f.results[1])
    end)

    local function test_wait_all(n, timeout, expects, tolerance)
      local function sleep(ms) thread.sleep(ms) end
      local list = {}
      for i = 1, n do
        list[#list + 1] = thread.spawn(sleep, i * TOLERANCE)
      end
      local function main()
        local res = thread.wait_all(list, timeout)
        local count = 0 -- fulfilled futures
        for i = 1, n do
          if list[i].results then
            count = count + 1
          else
            list[i]:abort()
          end
        end
        return res, count
      end
      local main_future = thread.spawn(main)
      local t0 = uv.now()
      thread.run()
      local elapsed  = uv.now() - t0
      assert.near(expects * TOLERANCE, elapsed, TOLERANCE)
      assert.equal(expects == n, main_future.results[1])
      assert.near(expects, main_future.results[2], tolerance)
    end

    it("can wait_all() for multiple coroutines to finish", function()
      test_wait_all(6, nil, 6, 0)
    end)

    it("can wait_all() for multiple coroutines with a timeout", function()
      test_wait_all(100, 3*TOLERANCE, 3, 1)
    end)

  end)

end)
