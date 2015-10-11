-------------------------------------------------------------------------------
-- Default Configuration (loaded by lift.config:init())
-------------------------------------------------------------------------------

local path = _G.require 'lift.path'

-- Default app_id and app_version
if not app_version then
  app_version = LIFT_VERSION
end

-- Default global_dir
if not global_dir then
  global_dir = '/usr/local/share/'..app_id
  if IS_WINDOWS then
    global_dir = 'c:/'..app_id
  end
end

-- Default user_dir
if not user_dir then
  if IS_WINDOWS then
    user_dir = USERPROFILE..'/'..app_id
  else
    user_dir = HOME..'/.'..app_id
  end
end

-- Default config_file_name
if not config_file_name then
  config_file_name = 'config.lua'
end

-- Add default entries to load_path
local function add_path(p)
  if path.is_dir(p) then
    self:insert_unique('load_path', p)
    return true
  end
end
-- project-specific files (from CWD up to FS root)
local dir = path.cwd()
while true do
  add_path(dir..'/.'..app_id)
  if #dir <= 1 or path.is_root(dir) then break end
  dir = path.dir(dir)
end
add_path(user_dir) -- user-specific files
add_path(global_dir) -- system-wide files
_G.assert(add_path(LIFT_SRC_DIR..'/init'), "couldn't find Lift's built-in files")
