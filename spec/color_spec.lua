describe('Module lift.color', function()

  local color = require 'lift.color'
  after_each(function() color.set_enabled(false) end)

  it('only encodes colors when enabled', function()
    local code = color.encode'reset;bright;red;onblack'
    assert.equal('\27[0;1;31;40m', code)
    assert.equal(nil, color.esc'red')
    assert.equal('', color.ESC'red')
    color.set_enabled(true)
    assert.equal(code, color.esc'reset;bright;red;onblack')
    assert.equal(code, color.ESC'reset;bright;red;onblack')
  end)

  it('returns nil in ESC() when disabled', function()
    local t = {color.esc'red;onblack'}
    t[#t + 1] = 'Red on black!'
    t[#t + 1] = color.esc'reset'
    assert.equal('Red on black!', table.concat(t))
    color.set_enabled(true)
    t = {color.esc'red;onblack'}
    t[#t + 1] = 'Red on black!'
    t[#t + 1] = color.esc'reset'
    assert.equal('\27[31;40mRed on black!\27[0m', table.concat(t))
  end)

  it('supports style tables', function()
    local t = {fg = 'red', bg = 'black', bold = true, dim = false, y = 'x'}
    assert.equal('', color.from_style(t))
    color.set_enabled(true)
    assert.equal(color.esc'reset;bold;red;onblack', color.from_style(t))
  end)

end)
