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
    assert.equal('/[a-zA-Z]/file_[?]%.cool', str.from_glob('/[a-zA-Z]/file_[?].cool'))
  end)

  it('offers split() to iterate substrings in a list', function()
    local t = {}
    for p in str.split'one;two,three' do t[#t + 1] = p end
    assert.same({'one', 'two', 'three'}, t)
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

end)
