describe("Module lift.utils", function()

  local utils = require 'lift.utils'

  it("offers keys_sorted()", function()
    assert.same({}, utils.keys_sorted{})
    assert.same({'a', 'bb', 'ccc'}, utils.keys_sorted{bb = 7, ccc = 5, a = 9})
    assert.error_matches(function() utils.keys_sorted'str' end,
      'table expected, got string')
  end)

  it("offers keys_sorted_as_string()", function()
    assert.same({1, 2, 'a', 'b', true},
      utils.keys_sorted_as_string{1, 2, a = 1, b = 2, [true] = 3})
  end)

  it("offers keys_sorted_by_type()", function()
    assert.same({true, 1, 2, 'a', 'b'},
      utils.keys_sorted_by_type{1, 2, a = 1, b = 2, [true] = 3})
  end)
end)
