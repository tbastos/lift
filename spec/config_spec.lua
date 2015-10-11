describe('Module lift.config should offer', function()

  local config = require 'lift.config'
  local diagnostics = require 'lift.diagnostics'

  before_each(function()
    config.reset()
    diagnostics.Verifier.set_new()
  end)

  it('a root scope with immutable vars', function()
    assert.not_nil(config.LIFT_VERSION)
    assert.equal(config._G, _G)
    assert.error_matches(function() config.LIFT_VERSION = 1 end, 'cannot be changed')
  end)

  it('access to env vars as a fallback', function()
    assert.not_nil(config.PATH)
    assert.Nil(config.NOT_AN_ENV_VAR)
  end)

  it('var auto-conversion to list', function()
    config.foo = 3
    assert.equal(config:get_list('foo'), config.foo, {3})
    config.bar = 'a;b;c;'
    assert.equal(config:get_list('bar'), config.bar, {'a', 'b', 'c'})
    config.nop = {x = 3}
    assert.equal(config:get_list('nop'), config.nop, {x = 3})
  end)

  it('function to insert into list vars', function()
    config.lst = 1
    assert.equal(1, config.lst)
    config:insert('lst', 2)
    assert.same({1, 2}, config.lst)
    config:insert('lst', 0, 1)
    assert.same({0, 1, 2}, config.lst)
  end)

  it('var auto-conversion to unique list', function()
    config.unique = 'a;c;b;c;b;d;'
    assert.same(config:get_unique_list('unique'), {'a', 'c', 'b', 'd'})
  end)

  it('function to insert into unique lists', function()
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

  it('nested scopes with var inheritance', function()
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

  it('load() to load a config file', function()
    local scope = config:new_scope()
    assert.equal(nil, scope.pi)
    scope:load('spec/data/config.lua')
    assert.equal(3.14, scope.pi)
    assert.equal('table', type(scope.path))

    assert.error_matches(function() scope:load'spec/data/config_syntax_err.lua' end,
      'unexpected symbol')
  end)

  it('init() to load available config files', function()
    assert.Nil(config.pi)
    config.load_path = 'spec/data'
    config.user_dir = 'spec/data/user'
    config.global_dir = 'spec/data/global'
    config.init()
    assert.equal(config.app_version, config.LIFT_VERSION)
    assert.equal(3.14, config.pi)
    assert.equal('user', config.opt1)
    assert.same({'A','a','b','c','d'}, config.list)
  end)

  it('init() aborts on first invalid config file', function()
    config.load_path = 'spec/data;spec/data/invalid_config'
    assert.error_matches(function() config.init() end, 'unexpected symbol')
  end)

end)

