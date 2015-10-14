describe('Module lift.template should support', function()

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

  it('simple expressions', function()
    local s = render_str([[
Hello {{first}}, {{sub[1]}}, {{sub[2]}}, {{ third:upper() }}!]],
      { first = 'One', sub = {true, 3}, third = 'Four' })
    assert.equal('Hello One, true, 3, FOUR!', s)
  end)

  it('statements', function()
    local s = render_str([[
{% for _, name in ipairs(names) do %}
 * {{name}};
{% end %}]],
      { names = {'One', 'Two', 'Three'}, ipairs = ipairs })
    assert.equal('\n * One;\n * Two;\n * Three;', s)
  end)

  it('includes', function()
    inject_file('/fake/templ.ct', [[
Hello {{name}}!
{% if child then %}
  {% if true then %}{( "./templ.ct" << child )}{% end %}
{% end %}]])
    local s = render_str('{( "/fake/templ.ct" )}',
      {name = "one", child = {name = "two", child = {name = "three"} } })
    assert.equal('Hello one!\n  Hello two!\n    Hello three!', s)
  end)

  it('comments', function()
    local s = render_str([[Hel{# this is a multi-line
        comment #}lo {{name}}!]], { name = "world" })
    assert.equal('Hello world!', s)
  end)

  it('loading of template files by absolute filename', function()
    template.set_env(_G)
    local s = render_file(config.LIFT_SRC_DIR..'/../spec/data/templates/row.lua',
      {k = 'pi', v = 3.14})
    assert.equal("pi = 3.14,\n", s)
  end)

  it('resolution of template files based on %{load_path}', function()
    config.reset()
    config.load_path = 'spec/data'
    local s = render_file('templates/file.lua', _G)
  end)

  it('handling of errors in template files', function()
    config.reset()
    config.load_path = 'spec/data'
    assert.error_matches(function() render_file('non_existing.lua') end,
      "cannot find template 'non_existing.lua'")
    assert.error_matches(function() render_file('templates/invalid.lua') end,
      "invalid.lua:2:")
  end)

end)
