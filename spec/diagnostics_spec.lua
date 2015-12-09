describe('lift.diagnostics', function()

  local function dummy() end -- keep this at line 3...

  local diagnostics = require 'lift.diagnostics'

  describe('when creating a diagnostic object', function()

    it('formats messages by interpolating variables', function()
      local d = diagnostics.new('remark: lift is awesome!', 5, 7)
      assert.True(diagnostics.is_a(d))
      assert.False(diagnostics.is_a('string'))
      assert.equal('remark', d.kind, d.level)
      assert.equal('lift is awesome!', d.message)
      assert.equal(5, d[1]) assert.equal(7, d[2])

      assert.error(function() diagnostics.new() end,
        "first arg must be a message")
      assert.error(function() diagnostics.new('no kind') end,
        "malformed diagnostic message 'no kind'")
      assert.error(function() diagnostics.new('crazy: kind') end,
        "unknown diagnostic kind 'crazy'")
    end)

    it('implements lazy formatting of messages', function()
      local three = diagnostics.new('remark: 3')
      local d = diagnostics.new('warning: ${1} + ${3} is not ${2}',
        1, '2', three.message)
      assert.equal('${1} + ${3} is not ${2}', d[0])
      assert.equal('1 + 3 is not 2', d.message)
      local remark = diagnostics.new('remark: Hey, ${1}!', d)
      assert.equal('Hey, warning: 1 + 3 is not 2!', remark.message)
      assert.equal('warning', d.level)
      assert.equal('remark', three.level, remark.level)
    end)

    it('supports table-based construction', function()
      local d = diagnostics.new({'remark: ${1}${2}${3} ${4}${5}',
        1, '2', 3}, 4, 5)
      assert.equal('123 ${MISSING:4}${MISSING:5}', d.message)
    end)

    it("can aggregate multiple diagnostics into one", function()
      local d1 = diagnostics.new('remark: a ${kind}')
      local d2 = diagnostics.new('warning: a ${kind}')
      local d3 = diagnostics.new('error: an ${kind}'):set_location(dummy)
      local a1 = diagnostics.aggregate('warning: ${n} diagnostic${s}', {d2})
      assert.equal([[
warning: 1 diagnostic
  (1) warning: a warning]], tostring(a1))
      local a2 = diagnostics.aggregate('error: ${n} diagnostic${s}',
        {d1, d2, d3})
      assert.equal([[
error: 3 diagnostics
  (1) remark: a remark
  (2) warning: a warning
  (3) spec/diagnostics_spec.lua:3: error: an error]], tostring(a2))
    end)
  end)

  it('supports diagnostic consumers', function()
    diagnostics.set_consumer(nil)
    assert.error(function() diagnostics.new('error: oops'):report() end,
      'undefined diagnostics consumer')
    assert.error(function() diagnostics.report('error: oops') end,
      'undefined diagnostics consumer')

    local last
    diagnostics.set_consumer(function(d) last = d end)
    local d = diagnostics.new('warning: this works')
    assert.equal(nil, last) d:report() assert.equal(d, last)
  end)

  it('provides Verifier for error handling and testing', function()
    -- setting a new consumer resets the error count
    local verifier = diagnostics.Verifier.set_new()
    assert.no_error(function() diagnostics.check_error() end)

    -- at any time we can raise a fatal diagnostic
    local fatal = diagnostics.new('fatal: killer')
    assert.error(function() fatal:report() end, fatal)
    assert.error(function() diagnostics.report('fatal: brace yourselves') end,
      {kind = 'fatal', level = 'fatal', [0] = 'brace yourselves'})

    local ok, err = pcall(diagnostics.report,
      'fatal: ${1} is coming', 'winter')
    assert.False(ok) assert.equal('fatal: winter is coming', tostring(err))

    -- check_error() raises the latest error diagnostic, if any
    assert.no_error(function() diagnostics.check_error() end)
    diagnostics.report('error: first')
    diagnostics.report('error: second')
    assert.error(function() diagnostics.check_error() end,
      {kind = 'error', level = 'error', [0] = 'second'})

    -- our verifier should have accumulated only the two errors
    assert.equal(2, #verifier)
    assert.equal('first', verifier[1].message)
    assert.equal('second', verifier[2].message)

    -- shorthand version of the above checks:
    assert.no_error(function() verifier:verify{'first', 'second'} end)
    assert.error_match(function() verifier:verify{'first'} end,
      'expected 1 but got 2 diagnostics')
    assert.error_match(function() verifier:verify{'first', 'nop'} end,
      'mismatch at diagnostic #2\nActual: error: second\nExpected: nop')

    -- verifier should receive all diagnostics except the 'ignored' ones
    diagnostics.report('ignored: not reported')
    assert.equal(2, #verifier)
    diagnostics.report('remark: reported')
    assert.equal(3, #verifier)
  end)

  it("provides wrap(f) to automatically report diagnostics", function()
    local f = diagnostics.trace('Pre!', 'Post!', function()
      diagnostics.new('error: zomg!')
        :source_location('dummy.lua', 'omg error', 5):report()
    end)
    local error_log = io.tmpfile()
    diagnostics.set_tracing(true)
    diagnostics.set_stderr(error_log)
    diagnostics.wrap(function() f() end)
    diagnostics.set_stderr(io.stderr)
    diagnostics.set_tracing(false)
    error_log:seek('set')
    local out = error_log:read('*a')
    assert.match([[
Pre!
dummy.lua:1:5: error: zomg!
Post! %[.*s%]
Total time .*, memory .*]], out)
  end)

end)
