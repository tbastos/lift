describe('lift.os', function()

  local os = require 'lift.os'
  local su = require 'spec.util'

  it('offers sh() to execute a shell command', su.async(function()
    local out, err = os.sh'echo Hello world!'
    assert.equal('Hello world!\n', out)
    assert.equal('', err)

    out, err = os.sh[[lua -e "io.stderr:write'Hello from stderr'"]]
    assert.equal('', out)
    assert.equal('Hello from stderr', err)

    out, err = os.sh'invalid_cmd error'
    assert.Nil(out)
    assert.match('command failed .* not found', err)
  end))

end)
