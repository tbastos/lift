describe("lift.util", function()

  local util = require 'lift.util'

  it("offers keys_sorted()", function()
    assert.same({}, util.keys_sorted{})
    assert.same({'a', 'bb', 'ccc'}, util.keys_sorted{bb = 7, ccc = 5, a = 9})
    assert.error_match(function() util.keys_sorted'str' end,
      'table expected, got string')
  end)

  it("offers keys_sorted_as_string()", function()
    assert.same({1, 2, 'a', 'b', true},
      util.keys_sorted_as_string{1, 2, a = 1, b = 2, [true] = 3})
  end)

  it("offers keys_sorted_by_type()", function()
    assert.same({1, 2, 'a', 'b', true},
      util.keys_sorted_by_type{b = 2, 1, 2, [true] = 3, a = 1})
  end)

  it("offers inspect_value()", function()
    assert.equal('3', util.inspect_value(3))
    assert.equal('true', util.inspect_value(true))
    assert.equal('"str"', util.inspect_value('str'))
    assert.match('table', util.inspect_value({}))
  end)

  it("offers inspect_key()", function()
    assert.equal('[3]', util.inspect_key(3))
    assert.equal('[true]', util.inspect_key(true))
    assert.equal('str', util.inspect_key('str'))
    assert.equal('["nasty\\\nstr"]', util.inspect_key('nasty\nstr'))
  end)

  it("offers inspect_flat_list()", function()
    assert.equal('3, 2, 1, true', util.inspect_flat_list{3, 2, 1, true})
    assert.Nil(util.inspect_flat_list({'tooooo loooooong'}, 10))
    assert.Nil(util.inspect_flat_list{1, {}})
  end)

  it("offers inspect_flat_table()", function()
    assert.equal('"a1", "a2", x = 1, y = 2, [true] = 3',
      util.inspect_flat_table{'a1', 'a2', x = 1, [true] = 3, y = 2})
    assert.Nil(util.inspect_flat_table({x = 'tooooo loooooong'}, 10))
    assert.Nil(util.inspect_flat_table{1, {}})
  end)

  it("offers inspect_table() and inspect()", function()
    local t = {true, [3]=3, ['2']=2, [4]=4, nested = {x = 1, y = 2, z = 3}}
    local expected = [[{
  [1] = true,
  [3] = 3,
  [4] = 4,
  ["2"] = 2,
  nested = {x = 1, y = 2, z = 3},
}]]
    assert.equal(expected, util.inspect_table(t))
    assert.equal(expected, util.inspect(t))

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
}]], util.inspect_table(t))
    assert.equal('metamethod', util.inspect(t))
  end)

end)
