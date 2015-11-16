describe("Module lift.loader", function()

  local loader = require 'lift.loader'
  local config = require 'lift.config'
  local diagnostics = require 'lift.diagnostics'

  setup(function()
    diagnostics.Verifier.set_new()
    config:new_parent('cli')
    config.load_path = 'spec/files;'..config.LIFT_SRC_DIR..'/files'
  end)
  teardown(function()
    config.reset()
  end)

  local function count(iterator)
    local n = 0
    while iterator() do n = n + 1 end
    return n
  end

  it("offers find_scripts() to find Lua files in the ${load_path}", function()
    local prev_lp = config.load_path
    config.load_path = 'spec/files/invalid'
    finally(function() config.load_path = prev_lp end)
    assert.equal(3, count(loader.find_scripts('init')))
    assert.equal(1, count(loader.find_scripts('initabc')))
    assert.equal(1, count(loader.find_scripts('init', 'abc')))
    assert.equal(0, count(loader.find_scripts('init', 'none')))
    assert.equal(5, count(loader.find_scripts('foo')))
    assert.equal(3, count(loader.find_scripts('foo', 'bar')))
    assert.equal(1, count(loader.find_scripts('foo', 'barabc')))
  end)

  it('offers init() to automatically run init scripts', function()
    assert.Nil(config.pi)
    config.load_path = 'spec/files'
    config.user_config_dir = 'spec/files/user'
    config.system_config_dir = 'spec/files/system'
    loader.init()
    assert.equal(config.APP_VERSION, config.LIFT_VERSION)
    assert.equal(3.14, config.pi)
    assert.equal('user', config.opt1)
    assert.same({'A','a','b','c','d'}, config.list)

    config.load_path = 'spec/files;spec/files/invalid'
    assert.error_matches(function() loader.init() end, 'unexpected symbol')
  end)

end)
