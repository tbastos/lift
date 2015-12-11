describe('lift.fs', function()

  local fs = require 'lift.fs'

  it('offers is_dir() to test if a directory exists', function()
    assert.False(fs.is_dir'nothing', fs.is_dir'README.md')
    assert.True(fs.is_dir'spec')
  end)

  it('offers is_file() to test if a file exists', function()
    assert.False(fs.is_file'nothing', fs.is_file'spec')
    assert.True(fs.is_file'README.md')
  end)

  it('mkdir_all() to create dirs with missing parents', function()
    assert.no_error(function()
      assert(fs.mkdir_all'sub1/sub2')
      assert(fs.rmdir('sub1/sub2'))
      assert(fs.rmdir('sub1'))
    end)
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

end)
