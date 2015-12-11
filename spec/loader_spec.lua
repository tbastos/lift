describe("lift.loader", function()

  local fs = require 'lift.fs'
  local path = require 'lift.path'
  local loader = require 'lift.loader'
  local config = require 'lift.config'
  local diagnostics = require 'lift.diagnostics'

  after_each(function()
    diagnostics.Verifier.set_new()
    config.reset()
    config:new_parent('cli')
    config.load_path = config.LIFT_SRC_DIR..'/files'
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
    local spec_dir = path.clean(config.LIFT_SRC_DIR..'/../spec')

    -- change the CWD during a call to f
    local function init_in_dir(dir)
      local cwd = fs.cwd()
      assert(fs.chdir(dir))
      local ok, err = pcall(loader.init, loader)
      assert(fs.chdir(cwd))
      if not ok then error(err, 0) end
    end

    it('runs init scripts ir the order listed in the ${load_path}', function()
      assert.Nil(config.pi)
      config.load_path = 'files'
      config.user_config_dir = 'files/user'
      config.system_config_dir = 'files/system'
      init_in_dir(spec_dir..'/files/templates')
      assert.equal(spec_dir, config.project_dir)
      assert.equal(spec_dir..'/Liftfile.lua', config.project_file)
      assert.equal(config.APP_VERSION, config.LIFT_VERSION)
      assert.equal(3.14, config.pi)
      assert.equal('user', config.opt1)
      assert.same({'A','a','b','c','d'}, config.list)

      config.load_path = 'files;files/invalid'
      assert.error_match(function()
        init_in_dir(spec_dir..'/files/templates')
      end, 'unexpected symbol')
    end)

    it("detects project_dir based on presence of Liftfile.lua", function()
      assert.Nil(config.project_dir)
      assert.error_match(function() init_in_dir(spec_dir..'/files/invalid/foo') end,
        "Liftfile.lua:1: lua_syntax_error: unexpected symbol")
      assert.matches('spec/files/invalid', config.project_dir)
      assert.matches('spec/files/invalid/Liftfile.lua', config.project_file)
    end)

    it("detects project_dir based on presence of .lift dir", function()
      assert.Nil(config.project_dir)
      init_in_dir(spec_dir..'/files/project1')
      assert.matches('files/project1', config.project_dir)
      assert.Nil(config.project_file)
    end)

  end)

end)
