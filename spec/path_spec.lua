describe('lift.path', function()

  local path = require 'lift.path'

  it('offers is_root() to test if path is lexically a root dir', function()
    assert.False(path.is_root'/foo', path.is_root'C:/foo', path.is_root'C:')
    assert.True(path.is_root'/', path.is_root'C:/')
  end)

  it('offers volume_name() to get the volume name from Windows paths', function()
    assert.equal('', path.volume_name'/foo/file.ext')
    assert.equal('X:', path.volume_name'X:/foo/file.ext')
  end)

  it('offers base() to get the last element of a path', function()
    assert.equal('file.ext', path.base'/foo/dir/file.ext')
    assert.equal('file.ext', path.base'C:/foo/dir/file.ext')
    assert.equal('dir', path.base'/foo/dir/')
    assert.equal('/', path.base'/')
    assert.equal('.', path.base'')
  end)

  it('offers dir() to get the directory of a path', function()
    assert.equal('/foo/dir', path.dir'/foo/dir/file.ext')
    assert.equal('C:/foo/dir', path.dir'C:/foo/dir/file.ext')
    assert.equal('/foo/dir', path.dir'/foo/dir/')
    assert.equal('/', path.dir'/')
    assert.equal('C:/', path.dir'C:/', path.dir'C:/foo')
    assert.equal('.', path.dir'', path.dir'C:', path.dir'file.ext')
  end)

  it('offers ext() to get the filename extension of a path', function()
    assert.equal('ext', path.ext'/dir/file.ext', path.ext'C:/dir/file.x.ext')
    assert.equal('', path.ext'/dir/file', path.ext'/dir/file.')
  end)

  it('offers clean() to normalize a path', function()
    assert.equal('..', path.clean'..')
    assert.equal('/', path.clean'/', path.clean'/..')
    assert.equal('C:/', path.clean'C:/', path.clean'C:/..')
    assert.equal('.', path.clean'', path.clean'.', path.clean'./')
    assert.equal('/foo/dir', path.clean'/foo/dir/')
    assert.equal('/foo/dir', path.clean'/foo/dir')
    assert.equal('/foo/dir', path.clean('/foo/dir', true))
    assert.equal('/foo/dir/', path.clean('/foo/dir/', true))
    assert.equal('/foo/dir/file.ext', path.clean'/foo/dir/file.ext')
  end)

  it('offers is_abs() to test if a path is absolute', function()
    assert.True(path.is_abs'/foo/file.ext', path.is_abs'C:/foo/file.ext')
    assert.False(path.is_abs'./foo/dir/', path.is_abs'file.ext')
  end)

  it('offers abs() to make a path absolute', function()
    assert.equal('/foo/file.ext', path.abs'/foo/file.ext')
    assert.equal('/foo/dir/', path.abs'/foo/dir/')
    assert.equal('/', path.abs'/')
    assert.equal(path.cwd(), path.abs'')
    assert.equal(path.cwd()..'/file', path.abs'file')
    assert.equal('/usr/local/*/file', path.abs('../*/file', '/usr/local/bin'))
    assert.equal('C:/usr/local/file', path.abs('../file', 'C:/usr/local/bin'))
    assert.equal('/usr/dir', path.abs('../dir', '/usr/local', true))
    assert.equal('/usr/dir/', path.abs('../dir/', '/usr/local', true))
  end)

  it('offers rel() to make a path relative to some other path', function()
    assert.equal('b/c', path.rel('/a', '/a/b/c'))
    assert.equal('b/c', path.rel('C:/a', 'C:/a/b/c'))
    assert.equal('../b/c', path.rel('/a', '/b/c'))
    assert.equal('../b/c', path.rel('C:/a', 'C:/b/c'))
    assert.equal('c', path.rel('a/b', 'a/b/c'))
    assert.equal('c', path.rel('./a/b', './a/b/c'))
    assert.equal('..', path.rel('./a/b/c', './a/b/'))
    assert.error(function() path.rel('/a', './b/c') end,
      "result depends on current dir")
  end)

  it('offers join() to join path elements', function()
    assert.equal('/usr/local', path.join('/usr', '', '', 'local'))
    assert.equal('/usr/local/bin', path.join('/./usr/', 'local', 'bin/'))
  end)

  it('offers split() to get the dir and file components of a path', function()
    assert.same({'/usr/local/',''}, {path.split('/usr/local/')})
    assert.same({'C:/usr/local/',''}, {path.split('C:/usr/local/')})
    assert.same({'/usr/local/','bin'}, {path.split('/usr/local/bin')})
    assert.same({'C:/usr/local/','bin'}, {path.split('C:/usr/local/bin')})
    assert.same({'C:/','usr'}, {path.split('C:/usr')})
    assert.same({'C:/',''}, {path.split('C:/')})
    assert.same({'','file.ext'}, {path.split('file.ext')})
  end)

  it('offers split_list() to iterate each path in a path list', function()
    local t = {}
    for p in path.split_list'/one;two/;three' do t[#t + 1] = p end
    assert.same({'/one', 'two/', 'three'}, t)
  end)

  it('offers is_dir() to test if a directory exists', function()
    assert.False(path.is_dir'nothing', path.is_dir'README.md')
    assert.True(path.is_dir'spec')
  end)

  it('offers is_file() to test if a file exists', function()
    assert.False(path.is_file'nothing', path.is_file'spec')
    assert.True(path.is_file'README.md')
  end)

  it('offers match() to test if a path matches a glob pattern', function()
    assert.True(path.match('/dir/file.ext', '/*/file.*'))
    assert.True(path.match('/dir/file.ext', '/*/file?ext'))
    assert.False(path.match('/dir/file.ext', '*/file.*'))
    assert.False(path.match('/dir/file.ext', '*file*'))
  end)

  it('mkdir_all() to create dirs with missing parents', function()
    assert.no_error(function()
      assert(path.mkdir_all'sub1/sub2')
      assert(path.rmdir('sub1/sub2'))
      assert(path.rmdir('sub1'))
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
      assert.same({'*.lua'}, path.glob_parse('*.lua', vars))
      assert.same({'*/fname.lua'}, path.glob_parse('*/${name}.lua', vars))
      assert.same({'*/fname.', vars.exts},
        path.glob_parse('*/${name}.${exts}', vars))
      -- set product of vars in glob patterns
      local list = {}
      local function collect(patt) list[#list+1] = patt end
      path.glob_product(path.glob_parse('*.lua', vars), collect)
      assert.same({'*.lua'}, list)
      list = {}
      path.glob_product(path.glob_parse('${name}.lua', vars), collect)
      assert.same({'fname.lua'}, list)
      list = {}
      path.glob_product(path.glob_parse('${exts}', vars), collect)
      assert.same(vars.exts, list)
      list = {}
      path.glob_product(path.glob_parse('${name}.${exts}', vars), collect)
      assert.same({'fname.png', 'fname.jpg'}, list)
      list = {}
      path.glob_product(path.glob_parse('${path}/${name}.${exts}', vars), collect)
      assert.same({'/var/fname.png', '/var/fname.jpg',
        '/usr/local/var/fname.png', '/usr/local/var/fname.jpg'}, list)
    end)

    it("can match a string against a glob pattern", function()
      assert.True(path.match('/x/y/z/file.jpg', '**/z/*.${exts}', vars))
      assert.True(path.match('/z/file.jpg', '**/z/*.${exts}', vars))
      assert.False(path.match('file.jpeg', '*.${exts}', vars))
    end)

    it("can find files using wildcards", function()
      local it = path.glob('*.md') ; assert.is_function(it)
      local filename = it() ; assert.is_string(filename)
      assert.match('/CONTRIBUTING%.md$', filename)
      assert.match('/README%.md$', it())
      assert.is_nil(it())
      assert.error(function() it() end, "cannot resume dead coroutine")
      assert.is_nil(path.glob('/invalid/*.md')())
      assert.match('/README.md$', path.glob('./REA*.??')())
      assert.match('/spec/files/user/init.lua$', path.glob('spec/*/user/ini*')())
      assert.match('/spec/files/init.lua$', path.glob('spec/*/init.lua')())
      assert.match('/spec/files/invalid/foo/z$', path.glob('**/z')())
      assert.error(function() path.glob('**')() end,
        "expected a name or pattern after wildcard '**'")
    end)

    it("wildcards **/ and /*/ ignore dot files by default", function()
      if path.is_dir('.git') then
        assert.is_nil(path.glob('**/HEAD')())
        assert.is_nil(path.glob('*/HEAD')())
        assert.is_nil(path.glob('./*/HEAD')())
        assert.is_string(path.glob('.*/HEAD')())
        assert.is_string(path.glob('./.*git/HEAD')())
      else
        pending("skipped some tests because lift/.git doesn't exist")
      end
    end)

    it('supports configurable ${var} and ${list} expansions', function()
      local it = path.glob('./${readme}.md', vars)
      assert.match('/README%.md$', it())
      assert.is_nil(it())

      assert.error(function() path.glob('${invalid}', vars) end,
        'no such variable ${invalid}')

      it = path.glob('${list}.md', vars)
      assert.match('/README%.md$', it())
      assert.is_nil(it())

      it = path.glob('spec/*/in${list}.lua', vars)
      assert.match('/spec/files/invalid/foo%.lua$', it())
      assert.is_nil(it())
    end)

    it('expands config variables by default', function()
      assert.is_string(path.glob('${PATH}/lua*')())
    end)

  end)

end)
