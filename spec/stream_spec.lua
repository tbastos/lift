describe('lift.stream', function()

  local stream = require 'lift.stream'
  local su = require 'spec.util'

  describe("readable stream", function()

    it("can be read synchronously", su.async(function()
      local list = {} ; for i = 1, 20 do list[i] = i end
      local s = stream.from_list(list)
      for i = 1, 20 do
        assert.equal(i, s:read())
      end
    end))

  end)

  describe("writable stream", function()

    it("can be written to synchronously", function()
      local list = {}
      local s = stream.to_list(list)
      local n = s.w_hwm * 2 + 3
      for i = 1, n do
        s:write(i)
      end
      s:write(nil)
      for i = 1, n do
        assert.equal(i, list[i])
      end
    end)

  end)

end)
