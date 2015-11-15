describe("Module lift.loader", function()

  local loader = require 'lift.loader'
  local config = require 'lift.config'
  local diagnostics = require 'lift.diagnostics'

  setup(function()
    diagnostics.Verifier.set_new()
    config:new_parent('cli')
    config.load_path = 'spec/files'
  end)
  teardown(function()
    config.reset()
  end)

  it("offers find_scripts() to find Lua files in the ${load_path}", function()
    -- assert.same({}, loader.find_scripts('init'))
  end)

  it('offers :init() to automatically run init scripts', function()
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
