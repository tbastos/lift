describe('Module lift.string should offer', function()

  local str = require 'lift.string'

  it('capitalize() to capitalize a string', function()
    assert.equal('Around_the_world', str.capitalize('around_the_world'))
    assert.equal('Give it away', str.capitalize('give it away'))
    assert.equal('Under the Bridge', str.capitalize('Under the Bridge'))
    assert.equal('By-the-way', str.capitalize('by-the-way'))
    assert.equal('-nothing', str.capitalize('-nothing'))
  end)

  it('camelize() to convert to camelCase', function()
    assert.equal('aroundTheWorld', str.camelize('around_the_world'))
    assert.equal('giveItAway', str.camelize('give it away'))
    assert.equal('UnderTheBridge', str.camelize('Under the Bridge'))
    assert.equal('byTheWay', str.camelize('by-the-way'))
  end)

  it('classify() to create a class name from a string', function()
    assert.equal('AroundTheWorld', str.classify('around_the_world'))
    assert.equal('GiveItAway', str.classify('give it away'))
    assert.equal('UnderTheBridge', str.classify('Under the Bridge'))
    assert.equal('ByTheWay', str.classify('by-the-way'))
  end)

  it('decamelize() to split camelCase using underscores', function()
    assert.equal('around_the_world', str.decamelize('around_the_world'))
    assert.equal('give_It_Away', str.decamelize('giveItAway'))
    assert.equal('Under_The_Bridge', str.decamelize('UnderTheBridge'))
    assert.equal('by-the-way', str.decamelize('by-the-way'))
  end)

  it('dasherize() to always separate words using a dash', function()
    assert.equal('around-the-world', str.dasherize('around_the_world'))
    assert.equal('give-it-away', str.dasherize('give it away'))
    assert.equal('UnderTheBridge', str.dasherize('UnderTheBridge'))
    assert.equal('by-the-way', str.dasherize('by-the-way'))
  end)

  it('to_bool() to convert a string to boolean', function()
    local bool = str.to_bool
    assert.equal(true, bool'1', bool'y', bool'TRUE', bool'yEs', bool'on')
    assert.equal(false, bool'0', bool'N', bool'false', bool'off', bool'no')
    assert.equal(nil, bool'2', bool'with', bool'disabled')
  end)

  it('escape_magic() to escape magic characters in Lua patterns', function()
    assert.equal('A%+%+ %(Hello%?%)', str.escape_magic('A++ (Hello?)'))
  end)

  it('from_glob() to convert glob patterns to Lua patterns', function()
    assert.equal('/some/file%.ext', str.from_glob('/some/file.ext'))
    assert.equal('/[^/]*/file%.xy[^/]', str.from_glob('/*/file.xy?'))
    assert.equal('/[a-zA-Z]/file_[%w]', str.from_glob('/[a-zA-Z]/file_[%w]'))
  end)

  it('expand() to interpolate strings containing ${vars}', function()
    local xp = str.expand
    assert.equal('Hello, world!', xp('${1}, ${2}!', {'Hello', 'world'}))
    assert.equal('$a = $b != ${c}',xp('$${1} = ${2} != ${c}', {'a', '$b'}))
    assert.equal('Hey Joe!', xp('${hey} ${name}!', {hey='Hey', name='Joe'}))
  end)

  it('expand_list() to expand a list of strings', function()
    local list = {'This is ${name}', 'v${num}', 1+2, '${invalid}'}
    assert.same({'This is lift', 'v1', '3', '${invalid}'},
      str.expand_list(list, { name = 'lift', num = 1 }))
  end)

end)
