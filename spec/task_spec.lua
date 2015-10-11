describe('Executing a DAG of tasks', function()

  local task = require 'lift.task'
  local diagnostics = require 'lift.diagnostics'

  setup(function() diagnostics.Verifier.set_new() end)

  -- aux method added to all tasks
  function task.Task:addOwnName(t) t[#t + 1] = self.name end

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
