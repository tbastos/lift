describe('lift.cli', function()

  local cli = require 'lift.cli'
  local config = require 'lift.config'
  local loader = require 'lift.loader'
  local diagnostics = require 'lift.diagnostics'

  local root, verifier
  before_each(function()
    config.reset()
    config:new_parent('cli')
    root = cli.new()
    verifier = diagnostics.Verifier.set_new()
  end)

  it('parses command args and calls command actions', function()
    local ok -- set to true when the root command is run
    root:action(function() ok = true end)
    ok = false; root:process{'abc'} ; assert.True(ok)
    assert.equal('abc', root.args[1])
  end)

  it('calls custom action upon command invocation', function()
    local called = false
    root:action(function(cmd)
      called = true
      local one, two, three = cmd:consume('one', 'two', 'three')
      assert.equal('one', one)
      assert.equal('two', two)
      assert.equal('three', three)
    end)
    root:process{'one', 'two', 'three', 'wasted'}
    assert.True(called)
    assert.same(verifier[#verifier],
      diagnostics.new("warning: unused argument '${1}'", 'wasted'))
    assert.error_match(function() root:process{'one', 'two'} end,
      'missing argument <three>')
  end)

  it('allows actions to return error messages', function()
    root:action(function() return 'booom' end)
    root:flag('f'):action(function() return 'oops' end)
    assert.error_match(function() root:process{} end, 'booom')
    assert.error_match(function() root:process{'-f'} end, 'oops')
  end)

  describe('when parsing args', function()
    -- we use a dummy command action while testing flags and options
    before_each(function() root:action(function() end) end)

    it('performs basic checks', function()
      local ok -- set to true when the root command is matched
      function root:matched() ok = true end
      ok = false; root:process{} ; assert.True(ok) -- empty args
      ok = false; root:process{''} ; assert.True(ok) -- empty string

      assert.error(function() root:process() end, 'missing args')
      assert.error(function() root:command'child':process{} end,
        'not a root command')
    end)

    it('accepts flags with and without arguments', function()
      root:flag'x' -- no default
      root:flag('y'):default(true):alias('Y')
      assert.equal(true, root.options.x.is_flag, root.options.y.is_flag)
      assert.equal(nil, root:get'x')
      assert.equal(true, root:get'y')

      root:process{'--y', 'arg'}
      assert.equal(nil, root:get'x')
      assert.equal(true, root:get'y')

      root:process{'arg1', '--x', 'arg2', '-y', 'arg3'}
      assert.equal(true, root:get'x', root:get'y')

      root:process{'--x=true', '-y=false'}
      assert.equal(true, root:get'x') assert.equal(false, root:get'y')

      root:process{'--x=no', '-y=no'}
      assert.equal(false, root:get'x') assert.equal(false, root:get'y')

      root:process{'--x=off', '--Y'}
      assert.equal(false, root:get'x') assert.equal(true, root:get'y')

      assert.error_match(function() root:process{'--X'} end,
        'unknown option %-%-X')

      assert.error_match(function() root:process{'--unknown'} end,
        'unknown option %-%-unknown')

      assert.error_match(function() root:process{'-x=what'} end,
        "option %-x: expected <bool>, got 'what'")
    end)

    it('calls action when a flag is matched', function()
      root:flag'inc':default(0):action(function(opt, val)
        opt.value = opt.value + 1
      end)
      assert.equal(0, root:get'inc')
      root:process{'---inc'}
      assert.equal(1, root:get'inc')
      root:process{'-inc', 'arg1', '--inc', 'arg2', '--inc'}
      assert.equal(4, root:get'inc')
    end)

    it('supports option aliases and arguments', function()
      root:option'name' -- no default
      root:option('greeting'):alias('g'):default('Hello')
      assert.equal(false, root.options.name.is_flag)
      assert.equal(nil, root:get'name')
      assert.equal('Hello', root:get'greeting')

      root:process{'arg1', '--name', 'Joe', '-g=Hey', 'arg2', 'arg3'}
      assert.equal('Joe', root:get'name')
      assert.equal('Hey', root:get'greeting')

      root:process{'arg1', '-name=key=value', '-g=X:P:K'}
      assert.equal('key=value', root:get'name')
      assert.equal('X:P:K', root:get'g')

      assert.error_match(function() root:process{'--g'} end,
        'option %-%-g: missing argument')
    end)

    it('calls action when an option is matched', function()
      root:option'path':alias'p':default({}):action(function(opt, val)
          table.insert(opt.value, val)
        end)
      assert.equal(0, #root:get'p')
      root:process{'-p=1,2', '-p', '3', '--path=4', '---path', '5,6'}
      assert.equal(4, #root:get'p')
    end)

    it('stores command args for later consumption', function()
      root:flag'f' root:option'o'
      assert.is_nil(root.args, root:get'f', root:get'o')
      root:process{'arg1', '-f', 'arg2', '-o', 'arg3', 'arg4'}
      assert.not_nil(root.args, root:get'f', root:get'o')
      assert.equal(3, #root.args)

      root:process{'-f', 'one', '-f', 'two', 'three'}
      local one, two, three = root:consume('one', 'two', 'three')
      assert.equal('one', one)
      assert.equal('two', two)
      assert.equal('three', three)
    end)

  end)

  it('supports subcommand hierarchies, command aliases and delegates', function()
    local called, with
    local function spy(cmd) called = cmd.name ; with = cmd.args end
    root:action(spy):option('o')
    local sub1 = root:command('sub1'):action(spy) ; sub1:option('o1')
    local sub2 = root:command('sub2'):action(spy) ; sub2:option('o')
    local sub3 = sub1:command('sub3'):action(spy) ; sub3:option('o')
    local sub4 = sub3:command('sub4'):action(spy) ; sub4:option('o')

    assert.equal('sub1', root:get_command('sub1').name)
    assert.equal('sub1 sub3', root:get_command('sub1 sub3').name)
    assert.equal('sub1 sub3 sub4', root:get_command('sub1 sub3 sub4').name)
    assert.error_match(function() root:get_command('sub1 nope') end,
      "no such command 'sub1 nope'")

    root:process{'x', 'sub1', '-o=1'}
    assert.equal('', called) ; assert.equal(2, #with)

    assert.error_match(function() root:process{'sub1', '-o=1', '-o2=2'} end,
      "unknown option %-o2 for command 'sub1'")

    sub1:alias 's1'
    root:process{'s1', 'x', '-o=1', '-o1=2', 'sub2'}
    assert.equal('1', root:get'o')
    assert.equal('sub1', called)
    assert.equal(2, #with)

    assert.error_match(function() root:process{'sub2', '-o1=1'} end,
      "unknown option %-o1 for command 'sub2'")

    root:process{'sub2', 'y', '-o', 'x'}
    assert.equal('sub2', called) ; assert.equal(1, #with)
    assert.equal('1', root:get'o') ; assert.equal('x', sub2:get'o')

    root:process{'-o=1', 'sub1', '-o1=2', 'sub3', '-o=3', 'x'}
    assert.equal('1', root:get'o') ; assert.equal('2', sub1:get'o1')
    assert.equal('sub1 sub3', called)
    assert.equal(1, #with) ; assert.equal('3', sub3:get'o')

    root:process{'-o=2', 'sub1', '-o1=3', 'sub3', '-o=4', 'sub4', 'x', '-o=5'}
    assert.equal('2', root:get'o') ; assert.equal('3', sub1:get'o1')
    assert.equal('4', sub3:get'o') ; assert.equal('sub1 sub3 sub4', called)
    assert.equal(1, #with) ; assert.equal('5', sub4:get'o')

    -- delegate 'del' to 'sub1 sub3 sub4'
    called = nil
    root:command('del'):delegate_to(root:get_command'sub1 sub3 sub4')
    root:process{'del'}
    assert.equal('sub1 sub3 sub4', called)
    assert.error_match(function() root:delegate_to('sub1') end,
      "expected a command object, got string")
  end)

  it("checks for name clashes", function()
    root:command'cmd':alias'c'
    root:option'opt':alias'o'
    assert.error(function() root:command'cmd' end, "redefinition of command 'cmd'")
    assert.error(function() root:command'c' end, "redefinition of command 'c'")
    assert.error(function() root:option'opt' end, "redefinition of option 'opt'")
    assert.error(function() root:option'o' end, "redefinition of option 'o'")
  end)

  describe("default root command", function()
    local exit = os.exit
    before_each(function()
      os.exit = function() error('os.exit') end -- luacheck: ignore
    end)
    after_each(function()
      os.exit = exit -- luacheck: ignore
    end)

    it("implements --help", function()
      local _, out = diagnostics.capture(function()
        root:process{'--help'}
      end)
      assert.match("Use 'lift help <command>' to read about a subcommand", out)
    end)

    it("implements help command", function()
      local _, out = diagnostics.capture(function()
        root:process{'help help'}
      end)
      assert.match("^Usage:.* help .* Print help for one command and exit", out)
    end)

    it("implements --version", function()
      local _, out = diagnostics.capture(function()
        root:process{'--version'}
      end)
      assert.equal(config.LIFT_VERSION, out)
    end)

  end)

  describe("default cli", function()

    before_each(function()
      config.load_path = config.LIFT_SRC_DIR..'/files'
      loader.load_all('cli', nil, root)
    end)

    it("implements 'config list'", function()
      local ok, out = diagnostics.capture(function()
        root:process{'my_var=1', '--color=no', 'config', 'list', 'my_var'}
      end)
      assert.True(ok)
      assert.equal('\n-- from cli\nmy_var = "1"\n', out)
    end)

  end)

end)
