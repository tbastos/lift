describe('lift.string', function()

  local str = require 'lift.string'

  it('offers capitalize() to capitalize a string', function()
    assert.equal('Around_the_world', str.capitalize('around_the_world'))
    assert.equal('Give it away', str.capitalize('give it away'))
    assert.equal('Under the Bridge', str.capitalize('Under the Bridge'))
    assert.equal('By-the-way', str.capitalize('by-the-way'))
    assert.equal('-nothing', str.capitalize('-nothing'))
  end)

  it('offers camelize() to convert to camelCase', function()
    assert.equal('aroundTheWorld', str.camelize('around_the_world'))
    assert.equal('giveItAway', str.camelize('give it away'))
    assert.equal('UnderTheBridge', str.camelize('Under the Bridge'))
    assert.equal('byTheWay', str.camelize('by-the-way'))
  end)

  it('offers classify() to create a class name from a string', function()
    assert.equal('AroundTheWorld', str.classify('around_the_world'))
    assert.equal('GiveItAway', str.classify('give it away'))
    assert.equal('UnderTheBridge', str.classify('Under the Bridge'))
    assert.equal('ByTheWay', str.classify('by-the-way'))
  end)

  it('offers decamelize() to split camelCase using underscores', function()
    assert.equal('around_the_world', str.decamelize('around_the_world'))
    assert.equal('give_It_Away', str.decamelize('giveItAway'))
    assert.equal('Under_The_Bridge', str.decamelize('UnderTheBridge'))
    assert.equal('by-the-way', str.decamelize('by-the-way'))
  end)

  it('offers dasherize() to always separate words using a dash', function()
    assert.equal('around-the-world', str.dasherize('around_the_world'))
    assert.equal('give-it-away', str.dasherize('give it away'))
    assert.equal('UnderTheBridge', str.dasherize('UnderTheBridge'))
    assert.equal('by-the-way', str.dasherize('by-the-way'))
  end)

  it('offers to_bool() to convert a string to boolean', function()
    local bool = str.to_bool
    assert.equal(true, bool'1', bool'y', bool'TRUE', bool'yEs', bool'on')
    assert.equal(false, bool'0', bool'N', bool'false', bool'off', bool'no')
    assert.equal(nil, bool'2', bool'with', bool'disabled')
  end)

  it('offers escape_magic() to escape magic characters in Lua patterns', function()
    assert.equal('A%+%+ %(Hello%?%)', str.escape_magic('A++ (Hello?)'))
  end)

  it('offers from_glob() to convert glob patterns to Lua patterns', function()
    assert.equal('/some/file%.ext', str.from_glob('/some/file.ext'))
    assert.equal('/[^/]*/file%.xy[^/]', str.from_glob('/*/file.xy?'))
    assert.equal('/.*/[^/]*%.lua', str.from_glob('/**/*.lua'))
    assert.equal('/[^/]*[^/]*%.lua', str.from_glob('/**.lua'))
    assert.equal('/[a-zA-Z]/file_[?]%.cool', str.from_glob('/[a-zA-Z]/file_[?].cool'))
  end)

  it('offers expand() to interpolate ${vars} in strings', function()
    local xp = str.expand
    assert.equal('Hello, world!', xp('${1}, ${2}!', {'Hello', 'world'}))
    assert.equal('$a = $b != ${MISSING:c}',
      xp('$${1} = ${2} != ${c}', {'a', '$b'}))
    assert.equal('Hey Joe!', xp('${hey} ${name}!', {hey='Hey', name='Joe'}))
    -- with recursive expansions
    assert.equal('five = 5', xp('${2+3} = ${${${2}+${3}}}',
      {1,2,3,4, ['2+3'] = 'five', five = 5}))
    -- with custom var function
    assert.equal('2,3,4', xp('${1},${2},${3}', nil, function(t, v) return v+1 end))
  end)

  it("offers format_value()", function()
    assert.equal('3', str.format_value(3))
    assert.equal('true', str.format_value(true))
    assert.equal('"str"', str.format_value('str'))
    assert.match('table', str.format_value({}))
  end)

  it("offers format_key()", function()
    assert.equal('[3]', str.format_key(3))
    assert.equal('[true]', str.format_key(true))
    assert.equal('str', str.format_key('str'))
    assert.equal('["nasty\\\nstr"]', str.format_key('nasty\nstr'))
  end)

  it("offers format_flat_list()", function()
    assert.equal('3, 2, 1, true', str.format_flat_list{3, 2, 1, true})
    assert.Nil(str.format_flat_list({'tooooo loooooong'}, 10))
    assert.Nil(str.format_flat_list{1, {}})
  end)

  it("offers format_flat_table()", function()
    assert.equal('"a1", "a2", x = 1, y = 2, [true] = 3',
      str.format_flat_table{'a1', 'a2', x = 1, [true] = 3, y = 2})
    assert.Nil(str.format_flat_table({x = 'tooooo loooooong'}, 10))
    assert.Nil(str.format_flat_table{1, {}})
  end)

  it("offers format_table() and format()", function()
    local t = {true, [3]=3, ['2']=2, [4]=4, nested = {x = 1, y = 2, z = 3}}
    local expected = [[{
  [1] = true,
  [3] = 3,
  [4] = 4,
  ["2"] = 2,
  nested = {x = 1, y = 2, z = 3},
}]]
    assert.equal(expected, str.format_table(t))
    assert.equal(expected, str.format(t))

    -- create cycles
    t.to_root = t
    t.nested.to_nested = t.nested
    setmetatable(t, {__tostring = function() return 'metamethod' end})
    assert.equal([[{
  [1] = true,
  [3] = 3,
  [4] = 4,
  ["2"] = 2,
  nested = {
    to_nested = @.nested,
    x = 1,
    y = 2,
    z = 3,
  },
  to_root = @,
}]], str.format_table(t))
    assert.equal('metamethod', str.format(t))
  end)
end)
