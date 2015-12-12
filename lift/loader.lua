------------------------------------------------------------------------------
-- Find and Load Lua Files in the ${load_path}
------------------------------------------------------------------------------

local loadfile = loadfile
local str_match, str_sub = string.match, string.sub

local glob = require'lift.fs'.glob
local path = require 'lift.path'
local config = require 'lift.config'
local diagnostics = require 'lift.diagnostics'

-- Returns an iterator over the Lua files in the ${load_path} that follow
-- a certain naming convention and match the 'type' and 'subtype' strings.
-- When subtype is omitted all subtypes are matched.
--   ./${type}.lua
--   ./${type}[_/]${subtype}.lua
--   ./${type}[_/]${subtype}[_/]*.lua
local separators = {'_', '/'}
local endings = {'.lua', '_*.lua', '/*.lua'}
local function find_scripts(type, subtype)
  local vars = {
    path = config:get_list'load_path',
    type = type,
    sep = separators,
    subtype = subtype,
    ending = endings,
  }
  local pattern = '${path}/${type}${sep}${subtype}${ending}'
  if not subtype then pattern = '${path}/${type}${ending}' end
  return glob(pattern, vars)
end

-- custom diagnostic for Lua syntax errors
diagnostics.levels.lua_syntax_error = 'fatal'
diagnostics.styles.lua_syntax_error = {prefix = 'syntax error:', fg = 'red'}

local load_file = diagnostics.trace('[loader] loading ${filename}',
  function(filename, ...)
    local chunk, err = loadfile(path.from_slash(filename), 't')
    if chunk then
      chunk(...)
    else
      local line, e = str_match(err, '^..[^:]+:([^:]+): ()')
      local msg = str_sub(err, e)
      diagnostics.new{'lua_syntax_error: ', message = msg,
        location = {file = filename, line = tonumber(line)}}:report()
    end
  end)

local load_all = diagnostics.trace(
  '[loader] running all ${type} ${subtype} scripts',
  '[loader] finished all ${type} ${subtype} scripts',
  function(type, subtype, ...)
    for filename in find_scripts(type, subtype) do
      load_file(filename, ...)
    end
  end)

local function run_init(filename)
  local scope = config:new_parent(filename)
  load_file(filename, scope)
  return scope
end

-- Executes all init scripts in the ${load_path}.
-- The first loaded script is "${LIFT_SRC_DIR}/files/init.lua" (hardcoded).
-- Other scripts are then loaded in the reverse order of entry in ${load_path}.
-- This usually means that system configs are loaded next, then user configs,
-- then local filesystem (project) configs.
local init = diagnostics.trace(
  '[loader] running init scripts',
  '[loader] finished init scripts',
  function()
    local top_scope -- keep track of the top config scope
    -- run the built-in init script
    local builtin_files = config.LIFT_SRC_DIR..'/files'
    top_scope = run_init(builtin_files..'/init.lua')
    -- run all init scripts in ${load_path}
    local list = {}
    for script in find_scripts('init') do
      list[#list+1] = script
    end
    for i = #list, 1, -1 do
      run_init(list[i])
    end
    -- run ${project_file} if available
    if config.project_file then
      run_init(config.project_file)
    end
    -- add built-in files to the ${load_path}
    config:insert_unique('load_path', builtin_files)
    return top_scope
  end)

return {
  find_scripts = find_scripts,
  init = init,
  load_all = load_all,
  load_file = load_file,
}
