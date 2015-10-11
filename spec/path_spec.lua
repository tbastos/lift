describe('Module lift.path should offer', function()

  local path = require 'lift.path'

  it('is_root() to test if path is lexically a root dir', function()
    assert.False(path.is_root'/foo', path.is_root'C:/foo', path.is_root'C:')
    assert.True(path.is_root'/', path.is_root'C:/')
  end)

  it('volume_name() to get the volume name from Windows paths', function()
    assert.equal('', path.volume_name'/foo/file.ext')
    assert.equal('X:', path.volume_name'X:/foo/file.ext')
  end)

  it('base() to get the last element of a path', function()
    assert.equal('file.ext', path.base'/foo/dir/file.ext')
    assert.equal('file.ext', path.base'C:/foo/dir/file.ext')
    assert.equal('dir', path.base'/foo/dir/')
    assert.equal('/', path.base'/')
    assert.equal('.', path.base'')
  end)

  it('dir() to get the directory of a path', function()
    assert.equal('/foo/dir', path.dir'/foo/dir/file.ext')
    assert.equal('C:/foo/dir', path.dir'C:/foo/dir/file.ext')
    assert.equal('/foo/dir', path.dir'/foo/dir/')
    assert.equal('/', path.dir'/')
    assert.equal('C:/', path.dir'C:/', path.dir'C:/foo')
    assert.equal('.', path.dir'', path.dir'C:', path.dir'file.ext')
  end)

  it('ext() to get the filename extension of a path', function()
    assert.equal('ext', path.ext'/dir/file.ext', path.ext'C:/dir/file.x.ext')
    assert.equal('', path.ext'/dir/file', path.ext'/dir/file.')
  end)

  it('clean() to normalize a path', function()
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

  it('is_abs() to test if a path is absolute', function()
    assert.True(path.is_abs'/foo/file.ext', path.is_abs'C:/foo/file.ext')
    assert.False(path.is_abs'./foo/dir/', path.is_abs'file.ext')
  end)

  it('abs() to make a path absolute', function()
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

  it('rel() to make a path relative to some other path', function()
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

  it('join() to join path elements', function()
    assert.equal('/usr/local', path.join('/usr', '', '', 'local'))
    assert.equal('/usr/local/bin', path.join('/./usr/', 'local', 'bin/'))
  end)

  it('split() to get the dir and file components of a path', function()
    assert.same({'/usr/local/',''}, {path.split('/usr/local/')})
    assert.same({'C:/usr/local/',''}, {path.split('C:/usr/local/')})
    assert.same({'/usr/local/','bin'}, {path.split('/usr/local/bin')})
    assert.same({'C:/usr/local/','bin'}, {path.split('C:/usr/local/bin')})
    assert.same({'C:/','usr'}, {path.split('C:/usr')})
    assert.same({'C:/',''}, {path.split('C:/')})
    assert.same({'','file.ext'}, {path.split('file.ext')})
  end)

  it('split_list() to iterate each path in a path list', function()
    local t = {}
    for p in path.split_list'/one:two/;three' do t[#t + 1] = p end
    assert.same({'/one', 'two/', 'three'}, t)
  end)

  it('is_dir() to test if a directory exists', function()
    assert.False(path.is_dir'nothing', path.is_dir'README.md')
    assert.True(path.is_dir'spec')
  end)

  it('is_file() to test if a file exists', function()
    assert.False(path.is_file'nothing', path.is_file'spec')
    assert.True(path.is_file'README.md')
  end)

  it('match() to test if a path matches a glob pattern', function()
    assert.True(path.match('/dir/file.ext', '/*/file.*'))
    assert.True(path.match('/dir/file.ext', '/*/file?ext'))
    assert.False(path.match('/dir/file.ext', '*/file.*'))
    assert.False(path.match('/dir/file.ext', '*file*'))
  end)

  -- counts how many files a glob() matched
  local function count_glob(...)
    local it, n = path.glob(...), 0
    while it() do n = n + 1 end return n
  end

  it('glob() to find files that match a pattern', function()
    local it = path.glob('*.md') ; assert.is_function(it)
    local filename = it() ; assert.is_string(filename)
    assert.True(filename:find('/README%.md$') ~= nil)
    assert.is_nil(it())
    assert.is_nil(it())

    it = path.glob('READ??.[a-z][a-z]')
    assert.equal(filename, it())
    assert.is_nil(it())

    it = path.glob('/invalid/*.md')
    assert.is_nil(it())

    assert.error_matches(function() path.glob('${var}?') end, 'must be separated')

    local mods, specs = count_glob('li*/*.lua'), count_glob('sp?c/*_spec.lua')
    assert.True(mods > 5, mods < 15, specs > 5, specs < 15)
  end)

  it('glob() with custom ${var} and ${list} expansions', function()
    local env = {name = 'README', list = {'invalid', 'README', 'spec'}}
    local it = path.glob('./${name}.md', env)
    local filename = it() ; assert.is_string(filename)
    assert.True(filename:find('/README%.md$') ~= nil)
    assert.is_nil(it())

    assert.error(function() path.glob('${invalid}', env) end,
      'no such variable ${invalid}')

    it = path.glob('${list}.md', env)
    assert.equal(filename, it())
    assert.is_nil(it())

    env.mods = {'nada', 'cli', 'string', 'template', 'invalid'}
    assert.equal(3, count_glob('./${list}/${mods}_spec.lua', env))
    assert.True(5 < count_glob('./${list}/*_spec*', env))
  end)

  it('glob() with default ${config} expansions', function()
    assert.True(count_glob('${PATH}/lua*') > 0)
  end)

  it('make() to create directory hierarchies', function()
    assert.no_error(function()
      assert(path.make'./sub1/sub2')
      assert(os.remove'./sub1/sub2')
      assert(os.remove'./sub1')
    end)
  end)

end)
