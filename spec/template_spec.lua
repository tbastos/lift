describe('lift.template', function()

  local config = require 'lift.config'
  local template = require 'lift.template'
  local function render(tpl_func, context)
    local t = {}
    tpl_func(function(s) t[#t+1] = s end, context)
    return table.concat(t)
  end
  local function render_str(str, context)
    return render(template.compile(str), context)
  end
  local function render_file(filename, context)
    return render(template.load(filename), context)
  end
  local function inject_file(name, content)
    template.cache[name] = template.compile(content, name)
  end

  it('supports simple expressions', function()
    local s = render_str([[
Hello {{first}}, {{sub[1]}}, {{sub[2]}}, {{ third:upper() }}!]],
      { first = 'One', sub = {true, 3}, third = 'Four' })
    assert.equal('Hello One, true, 3, FOUR!', s)
  end)

  it('supports statements', function()
    local s = render_str([[
{% for _, name in ipairs(names) do %}
 * {{name}};
{% end %}]],
      { names = {'One', 'Two', 'Three'}, ipairs = ipairs })
    assert.equal('\n * One;\n * Two;\n * Three;', s)
  end)

  it('supports partials', function()
    inject_file('/fake/templ.ct', [[
Hello {{name}}!
{% if child then %}
  {% if true then %}{( "./templ.ct" << child )}{% end %}
{% end %}]])
    local s = render_str('{( "/fake/templ.ct" )}',
      {name = "one", child = {name = "two", child = {name = "three"} } })
    assert.equal('Hello one!\n  Hello two!\n    Hello three!', s)
  end)

  it('supports comments', function()
    local s = render_str([[Hel{# this is a multi-line
        comment #}lo {{name}}!]], { name = "world" })
    assert.equal('Hello world!', s)
  end)

  it('loads templates by absolute filename', function()
    template.set_env(_G)
    local s = render_file(config.LIFT_SRC_DIR..'/../spec/files/templates/row.lua',
      {k = 'pi', v = 3.14})
    assert.equal("pi = 3.14", s)
  end)

  it('loads templates relative to the ${load_path}', function()
    config.reset()
    config:new_parent('cli')
    config.load_path = 'spec/files'
    local s = render_file('templates/file.lua', _G)
    assert.equal(s, [[
pi = 3.1415
{
  a = 1,
  b = true,
  c = {
    d = 'e',
  },
}]])
  end)

  it('handles errors in template files', function()
    config.reset()
    config:new_parent('cli')
    config.load_path = 'spec/files'
    assert.error_match(function() render_file('non_existing.lua') end,
      "cannot find template 'non_existing.lua'")
    assert.error_match(function() render_file('templates/invalid.lua') end,
      "invalid.lua:2:")
  end)

end)
