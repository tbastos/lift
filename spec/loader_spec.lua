describe("Module lift.loader", function()

  local loader = require 'lift.loader'
  local config = require 'lift.config'
  local diagnostics = require 'lift.diagnostics'

  after_each(function()
    diagnostics.Verifier.set_new()
    config.reset()
    config:new_parent('cli')
    config.load_path = 'spec/files;'..config.LIFT_SRC_DIR..'/files'
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

  describe("init()", function()

    it('runs init scripts ir the order listed in the ${load_path}', function()
      assert.Nil(config.pi)
      assert.Nil(config.cwd)
      config.load_path = 'spec/files'
      config.user_config_dir = 'spec/files/user'
      config.system_config_dir = 'spec/files/system'
      loader.init()
      assert.not_nil(config.cwd)
      assert.Nil(config.project_dir)
      assert.Nil(config.project_file)
      assert.equal(config.APP_VERSION, config.LIFT_VERSION)
      assert.equal(3.14, config.pi)
      assert.equal('user', config.opt1)
      assert.same({'A','a','b','c','d'}, config.list)

      config.load_path = 'spec/files;spec/files/invalid'
      assert.error_matches(function() loader.init() end, 'unexpected symbol')
    end)

    it("detects project_dir based on presence of Liftfile.lua", function()
      assert.Nil(config.project_dir)
      config.cwd = 'spec/files/invalid/foo'
      assert.error_matches(function() loader.init() end,
        "Liftfile.lua:1: unexpected symbol")
      assert.matches(config.project_dir, 'spec/files/invalid')
      assert.matches(config.project_file, 'spec/files/invalid/Liftfile.lua')
    end)

    it("detects project_dir based on presence of .lift dir", function()
      assert.Nil(config.project_dir)
      config.cwd = 'spec/files/project1'
      loader.init()
      assert.matches(config.project_dir, 'spec/files/project1')
      assert.Nil(config.project_file)
    end)

  end)

end)
