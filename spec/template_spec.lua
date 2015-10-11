describe('Module lift.template should', function()

  local template = require 'lift.template'
  local function render(str, context)
    local t = {}
    template.compile(str)(function(s) t[#t+1] = s end, context)
    return table.concat(t)
  end
  local function injectFile(name, content)
    template.cache[name] = template.compile(content, name)
  end

  it('simple expressions', function()
    local s = render([[
Hello {{first}}, {{sub[1]}}, {{sub[2]}}, {{ third:upper() }}!]],
      { first = 'One', sub = {true, 3}, third = 'Four' })
    assert.equal('Hello One, true, 3, FOUR!', s)
  end)

  it('statements', function()
    local s = render([[
{% for _, name in ipairs(names) do %}
 * {{name}};
{% end %}]],
      { names = {'One', 'Two', 'Three'}, ipairs = ipairs })
    assert.equal('\n * One;\n * Two;\n * Three;', s)
  end)

  it('includes', function()
    injectFile('/fake/templ.ct', [[
Hello {{name}}!
{% if child then %}
  {% if true then %}{( "./templ.ct" << child )}{% end %}
{% end %}]])
    local s = render('{( "/fake/templ.ct" )}',
      {name = "one", child = {name = "two", child = {name = "three"} } })
    assert.equal('Hello one!\n  Hello two!\n    Hello three!', s)
  end)

  it('comments', function()
    local s = render([[Hel{# this is a multi-line
        comment #}lo {{name}}!]], { name = "world" })
    assert.equal('Hello world!', s)
  end)

end)
