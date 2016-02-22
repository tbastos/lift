describe('lift.fs', function()

  local fs = require 'lift.fs'
  local stream = require 'lift.stream'
  local su = require 'spec.util'

  it('offers is_dir() to test if a directory exists', function()
    assert.False(fs.is_dir'nothing', fs.is_dir'README.md')
    assert.True(fs.is_dir'spec')
  end)

  it('offers is_file() to test if a file exists', function()
    assert.False(fs.is_file'nothing', fs.is_file'spec')
    assert.True(fs.is_file'README.md')
  end)

  it('offers mkdir_all() to create dirs with missing parents', function()
    assert.no_error(function()
      assert(fs.mkdir_all'sub1/sub2')
      assert(fs.rmdir('sub1/sub2'))
      assert(fs.rmdir('sub1'))
    end)
  end)

  it('offers scandir() to iterate dir entries', function()
    local t = {}
    for name, et in fs.scandir('spec/files/templates') do
      if not name:find('^%.') then
        t[#t+1] = name
      end
    end
    assert.same({'file.lua', 'row.lua', 'sub', 'table.lua'}, t)
  end)

  describe('file globbing', function()
    local vars = {
      name = 'fname',
      path = {'/var', '/usr/local/var'},
      exts = {'png', 'jpg'},
      readme = 'README',
      list = {'valid/foo', 'README', 'spec'},
    }

    it("accepts **, *, ?, [cclass] and n-fold variable expansions", function()
      -- parsing of glob patterns
      assert.same({'*.lua'}, fs.glob_parse('*.lua', vars))
      assert.same({'*/fname.lua'}, fs.glob_parse('*/${name}.lua', vars))
      assert.same({'*/fname.', vars.exts},
        fs.glob_parse('*/${name}.${exts}', vars))
      -- set product of vars in glob patterns
      local list = {}
      local function collect(patt) list[#list+1] = patt end
      fs.glob_product(fs.glob_parse('*.lua', vars), collect)
      assert.same({'*.lua'}, list)
      list = {}
      fs.glob_product(fs.glob_parse('${name}.lua', vars), collect)
      assert.same({'fname.lua'}, list)
      list = {}
      fs.glob_product(fs.glob_parse('${exts}', vars), collect)
      assert.same(vars.exts, list)
      list = {}
      fs.glob_product(fs.glob_parse('${name}.${exts}', vars), collect)
      assert.same({'fname.png', 'fname.jpg'}, list)
      list = {}
      fs.glob_product(fs.glob_parse('${path}/${name}.${exts}', vars), collect)
      assert.same({'/var/fname.png', '/var/fname.jpg',
        '/usr/local/var/fname.png', '/usr/local/var/fname.jpg'}, list)
    end)

    it("can match a string against a glob pattern", function()
      assert.True(fs.match('/dir/file.ext', '/*/file.*'))
      assert.True(fs.match('/dir/file.ext', '/*/file?ext'))
      assert.False(fs.match('/dir/file.ext', '*/file.*'))
      assert.False(fs.match('/dir/file.ext', '*file*'))
      assert.True(fs.match('/x/y/z/file.jpg', '**/z/*.${exts}', vars))
      assert.True(fs.match('/z/file.jpg', '**/z/*.${exts}', vars))
      assert.False(fs.match('file.jpeg', '*.${exts}', vars))
    end)

    it("can find files using wildcards", function()
      local it = fs.glob('*.md') ; assert.is_function(it)
      local filename = it() ; assert.is_string(filename)
      assert.match('/CONTRIBUTING%.md$', filename)
      assert.match('/README%.md$', it())
      assert.is_nil(it())
      assert.error(function() it() end, "cannot resume dead coroutine")
      assert.is_nil(fs.glob('/invalid/*.md')())
      assert.match('/README.md$', fs.glob('./REA*.??')())
      assert.match('/spec/files/user/init.lua$', fs.glob('spec/*/user/ini*')())
      assert.match('/spec/files/init.lua$', fs.glob('spec/*/init.lua')())
      assert.match('/spec/files/invalid/foo/z$', fs.glob('**/z')())
      assert.error(function() fs.glob('**')() end,
        "expected a name or pattern after wildcard '**'")
    end)

    it("wildcards **/ and /*/ ignore dot files by default", function()
      if fs.is_dir('.git') then
        assert.is_nil(fs.glob('**/HEAD')())
        assert.is_nil(fs.glob('*/HEAD')())
        assert.is_nil(fs.glob('./*/HEAD')())
        assert.is_string(fs.glob('.*/HEAD')())
        assert.is_string(fs.glob('./.*git/HEAD')())
      else
        pending("skipped some tests because lift/.git doesn't exist")
      end
    end)

    it('supports configurable ${var} and ${list} expansions', function()
      local it = fs.glob('./${readme}.md', vars)
      assert.match('/README%.md$', it())
      assert.is_nil(it())

      assert.error(function() fs.glob('${invalid}', vars) end,
        'no such variable ${invalid}')

      it = fs.glob('${list}.md', vars)
      assert.match('/README%.md$', it())
      assert.is_nil(it())

      it = fs.glob('spec/*/in${list}.lua', vars)
      assert.match('/spec/files/invalid/foo%.lua$', it())
      assert.is_nil(it())
    end)

    it('expands config variables by default', function()
      assert.is_string(fs.glob('${PATH}/lua*')())
    end)

  end)

  describe("convenience functions", function()
    it("offers read_file()/write_file() to read/write a whole file", function()
      local str = "One\nTwo\nThree\n"
      fs.write_file('temp_fs_rw_file', str)
      assert.equal(str, fs.read_file('temp_fs_rw_file'))
      fs.unlink('temp_fs_rw_file')
    end)
  end)

  describe("readable file stream", function()

    local LICENSE = fs.read_file('LICENSE')
    assert.is_string(LICENSE)
    assert.True(#LICENSE > 100 and #LICENSE < 8000)

    it("can read from a file (in one chunk)", su.async(function()
      local out = {}
      local to_out = stream.to_array(out)
      fs.read_from('LICENSE'):pipe(to_out):wait_finish()
      assert.same({LICENSE}, out)
    end))

    it("can read from a file (in many chunks)", su.async(function()
      local out = {}
      local to_out = stream.to_array(out, 20) -- with 50ms delay
      to_out.high_water = 3 -- forces readable to buffer
      local readable = fs.read_from('LICENSE', 100)
      readable.high_water = 3 -- forces reader to pause
      readable:pipe(to_out):wait_finish()
      assert.True(#out > 10) -- out should contain 11 chunks
      assert.equal(LICENSE, table.concat(out))
    end))

    it("push error if trying to read from inaccessible file", su.async(function()
      local out = {}
      local to_out = stream.to_array(out)
      local readable = fs.read_from('non_existing')
      assert.falsy(readable.read_error)
      assert.falsy(to_out.write_error)
      readable:pipe(to_out):wait_finish()
      assert.truthy(readable.read_error)
      assert.truthy(to_out.write_error)
      assert.equal('ENOENT: no such file or directory: non_existing',
        to_out.write_error.uv_err)
    end))
  end)

  describe("writable file stream", function()
    it("can write a string to a file", su.async(function()
      local sb = {'Hello world!\n'}
      local from_sb = stream.from_array(sb)
      from_sb:pipe(fs.write_to('tmp_hello')):wait_finish()
      assert.equal('Hello world!\n', fs.read_file('tmp_hello'))
      fs.unlink('tmp_hello')
    end))

    it("can write a string buffer to a file", su.async(function()
      local sb = {'Hello ', 'world!', '\nFrom string buffer\n'}
      local from_sb = stream.from_array(sb)
      from_sb:pipe(fs.write_to('tmp_hello')):wait_finish()
      assert.equal('Hello world!\nFrom string buffer\n', fs.read_file('tmp_hello'))
      fs.unlink('tmp_hello')
    end))

    it("can write a copy of a readable file", su.async(function()
      local path = 'LICENSE'
      fs.read_from(path):pipe(fs.write_to('tmp_copy')):wait_finish()
      assert.equal(fs.read_file(path), fs.read_file('tmp_copy'))
      fs.unlink('tmp_copy')
    end))
  end)

end)
