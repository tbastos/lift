describe('Module lift.config', function()

  local config = require 'lift.config'
  local diagnostics = require 'lift.diagnostics'

  before_each(function()
    config.reset()
    diagnostics.Verifier.set_new()
  end)

  it('is itself the global scope', function()
    assert.is_string(config.LIFT_VERSION)
  end)

  describe('internal root scope', function()
    it('has immutable vars', function()
      assert.error_matches(function() config.LIFT_VERSION = 1 end, 'cannot be changed')
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

      local s1 = config:new_scope()
      assert.equal('c1', s1.version)
      s1.version = 's1'
      assert.equal('s1', s1.version)
      assert.equal('c1', config.version)

      local s2 = s1:new_scope()
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

    it('have :load() to load a config file into the scope', function()
      local scope = config:new_scope()
      assert.equal(nil, scope.pi)
      scope:load('spec/data/config.lua')
      assert.equal(3.14, scope.pi)
      assert.equal(nil, config.pi)
      assert.equal('table', type(scope.path))

      assert.error_matches(function() scope:load'spec/data/config_syntax_err.lua' end,
        'unexpected symbol')
    end)

  end)

  it('offers :init() to automatically load config files', function()
    assert.Nil(config.pi)
    config.load_path = 'spec/data'
    config.user_config_dir = 'spec/data/user'
    config.system_config_dir = 'spec/data/system'
    config.init()
    assert.equal(config.app_version, config.LIFT_VERSION)
    assert.equal(3.14, config.pi)
    assert.equal('user', config.opt1)
    assert.same({'A','a','b','c','d'}, config.list)

    config.reset()
    config.load_path = 'spec/data;spec/data/invalid_config'
    assert.error_matches(function() config.init() end, 'unexpected symbol')
  end)

end)

