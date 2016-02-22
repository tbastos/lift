local fs = require 'lift.fs'
local los = require 'lift.os'
local path = require 'lift.path'
local task = require 'lift.task'
local config = require 'lift.config'
local loader = require 'lift.loader'
local template = require 'lift.template'
local diagnostics = require 'lift.diagnostics'

------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------

-- Returns whether the rock named `name` is installed.
-- If `min_version` is given, older rocks are ignored.
local function is_rock_installed(name, min_version)
  local v = los.try_sh('luarocks show --mversion '..name)
  if not v then return false end
  if min_version then
    local cur_major, cur_minor = v:match('(%d+)%.(%d+)')
    local min_major, min_minor = min_version:match('(%d+)%.(%d+)')
    if cur_major < min_major or
      (cur_major == min_major and cur_minor < min_minor) then
      return false, v
    end
  end
  return true, v
end

-- Installs a rock if necessary. The min_version string is optional, and
-- if given it should follow the format "major.minor" (two numbers only).
-- Raises an error if the rock cannot be installed.
local function require_rock(name, min_version)
  local ok, v = is_rock_installed(name, min_version)
  if ok then return v end
  -- install rock (raises an exception if the command fails)
  los.sh('luarocks install '..name)
  -- make sure the install succeeded and we met the min_version
  ok, v = is_rock_installed(name, min_version)
  if not ok then
    diagnostics.raise({"error: rock '${name}' version ${v} was installed "
      .. "but does not meet the required min_version (${min_version})",
        name = name, v = v, min_version = min_version}, 2)
  end
  return v
end

------------------------------------------------------------------------------
-- Generate Documentation
------------------------------------------------------------------------------

-- Returns a table with settings and vars to be passed to templates.
function task.get_doc_vars()
  local src_dir = path.abs('doc')
  local vars = {
    site        = {},
    config      = config,
    assets_dir  = src_dir..'/assets',
    content_dir = src_dir..'/content',
    output_dir  = src_dir..'/output',
    static_dir  = src_dir..'/static',
  }
  local init_script = src_dir..'/doc_vars.lua'
  if fs.access(init_script) then
    loader.load_file(init_script, vars)
  end
  return vars
end

local function parse_page(markdown_file)
  local markdown = fs.read_file(markdown_file)
  if markdown:sub(1, 1) ~= '{' then
    return {markdown = markdown} -- no Lua front matter
  end
  -- extract Lua front matter
  local lua_src = assert(markdown:match('^({.-\n})'))
  local chunk = assert(load('return '..lua_src, '@'..markdown_file, 't'))
  local page = chunk()
  assert(type(page) == 'table')
  page.markdown = markdown:sub(#lua_src + 1)
  return page
end

local function highlight_console(code)
  local sb = {'\n<pre class="console"><code>'}
  for line, ws in code:gmatch('([^\n]*)(\n*)') do
    local cwd, cmd = line:match('^([^$]*)$(.*)$')
    if cwd then
      sb[#sb+1] = '<span class="path">'..cwd
        ..'</span><span class="prompt">❯</span><span class="command">'
        ..cmd..'</span>'
    else
      sb[#sb+1] = line
    end
    sb[#sb+1] = ws
  end
  sb[#sb+1] = '</code></pre>\n'
  return table.concat(sb)
end

local function expand_code_block(lang, code)
  if lang == 'console' then return highlight_console(code) end
  return '\n<pre><code class="language-'..lang..'">'..code..'</code></pre>\n'
end

local function process_markdown(src)
  -- process fenced code blocks properly, since discount doesn't...
  return src:gsub("\n~~~ *([^\n]*) *\n(.-)\n~~~\n", expand_code_block)
end

-- Regenerates the documentation in OUTPUT_DIR
function task.doc()
  local v = task.get_doc_vars()
  -- create or clean the output dir
  if fs.access(v.output_dir) then
    los.sh('rm -Rf '..v.output_dir..'/*')
  else
    fs.mkdir(v.output_dir)
  end
  -- copy static content
  los.sh('cp -R '..v.static_dir..'/ '..v.output_dir)
  -- generate styles.css
  local css = los.sh('sassc -t compressed '..v.assets_dir..'/sass/main.scss')
  fs.write_file(v.output_dir..'/styles.css', css)
  -- process sections and create dirs
  for i, section_id in ipairs(v.sections) do
    local section = v.sections[section_id]
    section.id = section_id
    fs.mkdir(v.output_dir..section_id)
  end
  -- parse markdown files
  local pages = {}
  for src_file in fs.glob(v.content_dir..'/**/*.md') do
    local page = parse_page(src_file)
    page.url = src_file:sub(#v.content_dir + 1, -4)
    local section_id = path.dir(page.url)
    local section = v.sections[section_id]
    if not section then error('unknown section: '..section_id) end
    page.section = section
    section[#section+1] = page
    pages[#pages+1] = page
  end
  v.pages = pages
  -- sort pages within sections
  local function compare(a, b)
    local wa, wb = a.weight or 1000, b.weight or 1000
    return wa == wb and a.title_short < b.title_short or wa < wb
  end
  for i, section_id in ipairs(v.sections) do
    local section = v.sections[section_id]
    table.sort(section, compare)
  end
  -- generate HTML
  require_rock('discount')
  local discount = require 'discount'
  local page_tpl = template.load('page.html', v.assets_dir..'/templates/')
  for i, page in ipairs(pages) do
    local f = assert(io.open(v.output_dir..page.url..'.html', 'w'))
    local markdown = process_markdown(page.markdown)
    local doc = assert(discount.compile(markdown, 'toc', 'strict'))
    page.body = doc.body
    page.index = doc.index
    v.page = page
    page_tpl(function(s) f:write(s) end, v)
    f:close()
  end
end

------------------------------------------------------------------------------
-- Release Management (use `lift new_version=x.y.z` to prepare a new release)
------------------------------------------------------------------------------

-- Checks and returns the current version string
function task.get_version()
  local version = config.LIFT_VERSION
  -- make sure it matches the version in config.lua
  local config_src = fs.read_file('lift/config.lua')
  local config_ver = config_src:match("set_const%('APP_VERSION', '([^']*)'%)")
  if version ~= config_ver then
    diagnostics.report('fatal: current lift version (${1}) does not match '
      .. 'the version in config.lua (${2})', version, config_ver)
  end
  return version
end

-- Generates lift-VERSION-0.rockspec
local function generate_rockspec(version)
  local tpl = assert(template.load('lift.rockspec'))
  local filename = 'lift-'..version..'-0.rockspec'
  local f = assert(io.open(filename, 'w'))
  tpl(function(s) f:write(s) end, {
      version = version,
      base_dir = config.project_dir,
      modules = fs.glob('lift/**/*.lua')
    })
  f:close()
end

-- Updates the current version string
function task.set_version(new_version)
  if not new_version:match('%d+%.%d+%.%d+') then
    diagnostics.report("fatal: bad version '${1}' (expected d.d.d)", new_version)
  end
  local v = task.get_version()
  generate_rockspec(new_version)
  local cur_config = fs.read_file('lift/config.lua')
  local new_config, count = cur_config:gsub("set_const%('APP_VERSION', '"..v.."'",
    "set_const('APP_VERSION', '"..new_version.."'")
  assert(count == 1, "failed to update version string in config.lua")
  fs.write_file('lift/config.lua', new_config)
end

------------------------------------------------------------------------------
-- Default: update the necessary files
------------------------------------------------------------------------------

function task.default()
  generate_rockspec('scm') -- update lift-scm-0.rockspec
  if config.new_version then
    task.set_version(config.new_version)
  end
end

