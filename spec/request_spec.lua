describe('lift.request', function()

  local req = require 'lift.request'
  local stream = require 'lift.stream'
  local su = require 'spec.util'

  it("can fetch an HTML page", su.async(function()
    local sb = {} -- string buffer containing the page
    req('www.google.com/invalid_url'):pipe(stream.to_array(sb)):wait_finish()
    assert.match('404 Not Found', table.concat(sb))
  end))

  local function try_get(url)
    return function()
      local rs = req(url)
      repeat local data = rs:read() until data == nil
      assert(not rs.read_error)
    end
  end

  it("pushes errors onto the stream", su.async(function()
    assert.no_error(try_get('www.google.com/invalid_url'))
    assert.error_matches(try_get('-s www.google.com'), 'malformed URL')
    assert.error_matches(try_get('invalid.url'), 't resolve host')
    assert.error_matches(try_get('weird://protocol.com'),
      'Protocol .- not supported')
  end))

  it("can fetch a PNG image", su.async(function()
    local sb = {} -- string buffer containing the page
    req('www.google.com'):pipe(stream.to_array(sb)):wait_finish()
    local html = table.concat(sb)
    assert.equal('</html>', html:sub(-7))
    -- find a PNG
    local png_path = html:match([=[["'(]([^"'()]*nav_logo[^"'()]*%.png)["')]]=])
    if not png_path then
      print('Failed to find .png in page: ', html)
    end
    assert.is_string(png_path)
    -- download the PNG
    local sb2 = {}
    req('www.google.com'..png_path):pipe(stream.to_array(sb2)):wait_finish()
    local content = table.concat(sb2)
    assert.True(#content > 5000) -- size of the PNG
  end))

end)
