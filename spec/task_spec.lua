describe("A lift.task", function()

  local task = require 'lift.task'
  local diagnostics = require 'lift.diagnostics'

  before_each(function()
    diagnostics.Verifier.set_new()
  end)
  after_each(function()
    task:reset()
  end)

  describe("task group", function()

    it("is hierarchical", function()
      local root = task
      assert.equal('', root.name)
      assert.Nil(root.parent)
      assert.equal('', tostring(root))

      local child1 = root:group('child1')
      assert.equal('child1', child1.name)
      assert.equal(root, child1.parent)
      assert.equal(child1, root.child1)
      assert.equal('child1', tostring(child1))

      local grandchild1 = child1:group('grandchild1')
      assert.equal('grandchild1', grandchild1.name)
      assert.equal(child1, grandchild1.parent)
      assert.equal(grandchild1, child1.grandchild1)
      assert.equal('child1.grandchild1', tostring(grandchild1))

      local child2 = root:group('child2')
      assert.equal('child2', child2.name)
      assert.equal(root, child2.parent)
      assert.equal(child2, root.child2)
      assert.equal('child2', tostring(child2))
    end)

    it("allows definition of tasks as method declarations", function()
      function task:task1() end
      function task:task2() end
      local subgroup = task:group 'subgroup'
      function subgroup:task1() end
      assert.equal('table', type(task.task1), type(subgroup.task1))
      assert.equal('task2', task.task2.name)
      assert.equal(task, task.task2.group)
      assert.equal(subgroup, subgroup.task1.group)
      assert.equal('subgroup:task1', tostring(task.subgroup.task1))
      if _ENV then -- Lua 5.2+
        assert.error_matches(function() function task.func() end end,
          "tasks must be declared as :methods%(%) not %.functions%(%)")
      end
    end)

    it("forbids invalid task names and non-task values", function()
      assert.error_matches(function() task[1] = function(self)end end,
        'expected a task name, got 1')
      assert.error_matches(function() task['1x'] = function(self)end end,
        'expected a task name, got "1x"')
      assert.error_matches(function() task['a:b'] = function(self)end end,
        'expected a task name, got "a:b"')
      assert.error_matches(function() task['a b'] = function(self)end end,
        'expected a task name, got "a b"')
    end)

    it("can find subgroups and tasks", function()
      function task:t1() end
      local child = task:group 'child'
      function child:t2() end
      local grandchild = child:group 'grandchild'
      function grandchild:t3() end
      assert.equal(child, task:get_group'child')
      assert.equal(grandchild, task:get_group'child.grandchild')
      assert.error_matches(function() task:get_group'grandchild' end,
        "no such group '.grandchild'")
      assert.error_matches(function() task:get_group'child.grandchild.ggc' end,
        "no such group 'child.grandchild.ggc'")
      assert.equal(task.t1, task:get_task't1', task:get_task'.t1')
      assert.equal(child.t2, task:get_task'child.t2', task:get_task'child:t2')
      assert.equal(grandchild.t3, task:get_task'child.grandchild:t3')
      assert.error_matches(function() task:get_task'child.none' end,
        "no such task 'child.none'")
    end)

  end)

  describe("task", function()

    it("can be called as normal functions with a single arg", function()
      local v = 0
      function task:add_two() v = v + 2 end
      function task:add_arg(arg) v = v + arg end
      task.add_two()
      assert.equal(2, v)
      task.add_two()
      assert.equal(2, v)
      v = 0
      task.add_arg(3)
      assert.equal(3, v)
      task.add_arg(2)
      assert.equal(5, v)
      task.add_arg(2)
      assert.equal(5, v)
      assert.error_matches(function() task:add_two() end,
        "tasks must be called as %.functions%(%) not :methods%(%)")
      assert.error_matches(function() task.add_arg(4, 2) end,
        "tasks can only take one argument")
    end)

  end)

  describe("task set", function()

    it("is defined using 'task{t1, t2, ...}'", function()
      function task:t1() end
      function task:t2() end
      local sub = task:group('sub')
      function sub:t3() end
      assert.equal('TaskSet{t1, t2}', tostring(task{task.t1, task.t2}))
      assert.equal('TaskSet{sub:t3, t1, t2}', tostring(task{task.t2, task.t1, sub.t3}))
    end)

    it("can be invoked like a task", function()
      local v = 0
      function task:add_two() v = v + 2 end
      function task:add_five() v = v + 5 end
      function task:add_arg(arg) v = v + arg end
      task{task.add_two, task.add_five, task.add_arg}(3)
      assert.equal(10, v)
      task{task.add_two, task.add_five}()
      assert.equal(17, v)
      task{task.add_two, task.add_five}()
      assert.equal(17, v)
      task.add_arg(3)
      assert.equal(17, v)
      task.add_arg(4)
      assert.equal(21, v)
    end)

  end)

  --[[
  describe('when executing a DAG of tasks', function()

    -- aux method added to all tasks
    -- function task.Task:addOwnName(t) t[#t + 1] = self.name end

    it('should invoke methods in topo-sorted order', function()
      local a = { name = 'a' }
      local c = { name = 'c' } a.requires = { c }
      local b = { name = 'b', requires = { c } }
      local d = { name = 'd', requires = { a, b }}
      local root = { name = 'root', requires = { a, b, c, d } }
      local t = {} task.execute(root, 'addOwnName', t)
      assert.equal('c, a, b, d, root', table.concat(t, ', '))
    end)

    it('should detect cycles', function()
      local a = { name = 'a' }
      local b = { name = 'b' }
      local c = { name = 'c' } b.requires = { a, c }
      local d = { name = 'd' } c.requires = { d } d.requires = { b }
      local root = { name = 'root', requires = { a, b, c, d } }
      local ok, diag = pcall(task.execute, root, 'addOwnName', {})
      assert.False(ok)
      assert.equal("'b' -> 'c' -> 'd' -> 'b'", diag[1])
    end)

    it('should detect missing methods', function()
      local a = { name = 'a', method = function() end }
      local b = { name = 'b', method = function() end }
      local c = { name = 'c' }
      local root = { name = 'root', requires = { a, b, c } }
      assert.error(function() task.execute(root, 'method') end,
        "task 'c' does not support action 'method'")
    end)

  end)
  ]]

end)
