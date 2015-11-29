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
    local function f_a(arg, extra) return 1, 2, arg, extra end
    local function f_b() return nil, 'omg' end
    local a = async(f_a, 1337)
    local b = async(f_b)
    assert.matches('lift.async.Future%(.*, 1337%)', tostring(a))
    assert.falsy(a.results)
    assert.falsy(b.results)
    async.run()
    assert.same({1, 2, 1337}, a.results)
    assert.same({nil, 'omg'}, b.results)
  end)

  describe("coroutines", function()

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
      assert.is_table(sleep_30.results)
      assert.True(sleep_30.results[2] < sleep_60.results[2])
      assert.True(sleep_60.results[2] < sleep_90.results[2])
    end)

    it("can wait() for another coroutine to finish", function()
      local v = 1
      local function add_two() async.sleep(0) v = v + 2 end
      local function times_two() v = v * 2 end
      local function wait_times_two(future) async.wait(future) v = v * 2 end
      -- without wait
      async(add_two)
      async(times_two)
      async.run()
      assert.equal(4, v)
      -- with wait
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
    end)

    it("can wait() for a coroutine with a timeout", function()
      local function short_task() async.sleep(20) end
      local function long_task() async.sleep(60) end
      local function patient_wait(future) return async.wait(future, 80) end
      local function impatient_wait(future) return async.wait(future, 40) end
      -- successfully wait for a short task
      local f = async(impatient_wait, async(short_task))
      async.run()
      assert.True(f.results[1])
      -- unsuccessfully wait for a long task
      f = async(impatient_wait, async(long_task))
      async.run()
      assert.False(f.results[1])
      -- successfully wait for a long task
      f = async(patient_wait, async(long_task))
      async.run()
      assert.True(f.results[1])
    end)

    it("can wait_all() for multiple coroutines to finish", function()
      local function sleep(ms) async.sleep(ms) end
      local function main(n)
        local list = {}
        for i = 1, n do
          list[#list + 1] = async(sleep, i * TOLERANCE)
        end
        async.wait_all(list)
        local count = 0 -- fulfilled futures
        for i = 1, n do
          if list[i].results then
            count = count + 1
          end
        end
        return count
      end
      local n = 6
      local future = async(main, n)
      local t0 = uv.now()
      async.run()
      local elapsed  = uv.now() - t0
      assert.equal(n, future.results[1])
      assert.near(n * TOLERANCE, elapsed, TOLERANCE)
    end)

  end)

end)
