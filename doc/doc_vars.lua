local path = require 'lift.path'

local v = ... -- table of vars that is passed to templates

------------------------------------------------------------------------------
-- Global Variables
------------------------------------------------------------------------------

v.site.title = 'Lift'
v.site.subtitle = 'Lua automation tool and scripting framework'

v.github_url = 'https://github.com/tbastos/lift'
v.luarocks_url = 'https://luarocks.org/modules/tbastos/lift'
v.base_edit_url = 'https://github.com/tbastos/lift/edit/master/doc/content'

-- organize content into sections
v.sections = {
  -- list of section ids (sets the order)
  '/', '/api',
  -- mapping of ids to section data
  ['/'] = {title='Documentation', title_short='Documentation'},
  ['/api'] = {title='API Reference', title_short='API Reference'},
}

------------------------------------------------------------------------------
-- Helper Methods
------------------------------------------------------------------------------

function v.to_file(abs_url)
  return path.rel(path.dir(v.page.url), abs_url)
end

function v.to_page(page_id)
  return v.to_file(page_id..'.html')
end

