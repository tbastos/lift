describe("lift.scheduler", function()

  local scheduler = require 'lift.scheduler'

  it("offers run() to schedule all tasks to completion", function()
    scheduler.run()
  end)

  it("offers spawn(f, arg) to create a task to run f(arg)", function()
    local function f_a(arg, extra) return 1, 2, arg, extra end
    local function f_b() return nil, 'omg' end
    local a = scheduler.spawn(f_a, 1337)
    local b = scheduler.spawn(f_b)
    assert.falsy(a.results)
    assert.falsy(b.results)
    scheduler.run()
    assert.same({1, 2, 1337}, a.results)
    assert.same({nil, 'omg'}, b.results)
  end)

  it("offers sleep() to suspend the current task and resume later", function()
    local function test_sleep(dt) return scheduler.sleep(dt) end
    local sleep_50 = scheduler.spawn(test_sleep, 50)
    local sleep_20 = scheduler.spawn(test_sleep, 20)
    scheduler.run()
    assert.near(20, sleep_20.results[1], 5)
    assert.near(50, sleep_50.results[1], 5)
    assert.True(sleep_20.results[2] < sleep_50.results[2])
  end)

end)
