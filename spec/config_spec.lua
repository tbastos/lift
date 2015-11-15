describe('Module lift.config', function()

  local config = require 'lift.config'
  local diagnostics = require 'lift.diagnostics'

  before_each(function()
    config.reset()
    config:new_parent('cli')
    diagnostics.Verifier.set_new()
  end)

  it('is itself the global scope', function()
    assert.is_string(config.LIFT_VERSION)
  end)

  describe('internal root scope', function()
    it('has immutable vars', function()
      config.set_const('MY_CONST', 42)
      assert.equal(42, config.MY_CONST)
      assert.error_matches(function() config.MY_CONST = 1 end, 'cannot be changed')
    end)

    it('reads env vars as a fallback', function()
      assert.not_nil(config.PATH)
      assert.Nil(config.NOT_AN_ENV_VAR)
    end)
  end)

  describe('scopes', function()

    it('support nested scopes', function()
      assert.Nil(config.version)
      config.version = 'c1'
      assert.equal('c1', config.version)

      local s1 = config:new_child()
      assert.equal('c1', s1.version)
      s1.version = 's1'
      assert.equal('s1', s1.version)
      assert.equal('c1', config.version)

      local s2 = s1:new_child()
      assert.equal('s1', s2.version)
      s2.version = 's2'
      assert.equal('s2', s2.version)
      assert.equal('s1', s1.version)
    end)

    it('auto-convert vars to list with :get_list()', function()
      config.foo = 3
      assert.equal(config:get_list('foo'), config.foo, {3})
      config.bar = 'a;b;c;'
      assert.equal(config:get_list('bar'), config.bar, {'a', 'b', 'c'})
      config.nop = {x = 3}
      assert.equal(config:get_list('nop'), config.nop, {x = 3})
    end)

    it('have :insert() to insert into list vars', function()
      config.lst = 1
      assert.equal(1, config.lst)
      config:insert('lst', 2)
      assert.same({1, 2}, config.lst)
      config:insert('lst', 0, 1)
      assert.same({0, 1, 2}, config.lst)
    end)

    it('auto-convert vars to unique list with :get_unique_list()', function()
      config.unique = 'a;c;b;c;b;d;'
      assert.same(config:get_unique_list('unique'), {'a', 'c', 'b', 'd'})
    end)

    it('have :insert_unique() to insert into unique lists', function()
      config:insert_unique('unq', 2)
      config:insert_unique('unq', 5)
      config:insert_unique('unq', 2)
      assert.same({2, 5}, config.unq)
      config:insert_unique('unq', 5, 1) -- moves 5 to pos 1
      assert.same({5, 2}, config.unq)
      config:insert_unique('unq', 1, 2) -- inserts 1 at pos 2
      assert.same({5, 1, 2}, config.unq)
      config:insert_unique('unq', 5) -- does nothing
      assert.same({5, 1, 2}, config.unq)
      config:insert_unique('unq', 5, 3) -- moves 5 to pos 3
      assert.same({1, 2, 5}, config.unq)
    end)

  end)

end)

