------------------------------------------------------------------------------
-- Encoding of ANSI color escape sequences
------------------------------------------------------------------------------

local codes = {
  -- attributes
  reset     = 0,
  clear     = 0,
  bold      = 1,
  bright    = 1,
  dim       = 2,
  underline = 4,
  blink     = 5,
  reverse   = 7,
  hidden    = 8,
  -- foreground
  black     = 30,
  red       = 31,
  green     = 32,
  yellow    = 33,
  blue      = 34,
  magenta   = 35,
  cyan      = 36,
  white     = 37,
  -- background
  onblack   = 40,
  onred     = 41,
  ongreen   = 42,
  onyellow  = 43,
  onblue    = 44,
  onmagenta = 45,
  oncyan    = 46,
  onwhite   = 47,
}

-- given a string such as 'reset;red;onblack' returns a escape sequence
local str_gsub = string.gsub
local function encode(seq)
  return '\27[' .. str_gsub(seq, '([^;]+)', codes) .. 'm'
end

-- colors are disabled by default, use set_enabled()
local enabled = false
local function set_enabled(v) enabled = v end

-- =encode(seq) if colors are enabled; otherwise returns empty string
local function ESC(seq) if enabled then return encode(seq) end return '' end

-- =encode(seq) if colors are enabled; otherwise returns nil
local function esc(seq) if enabled then return encode(seq) end return nil end

-- encodes an escape sequence based on a style  table like {fg='red',
-- bg='black', bold=true} etc. Returns an empty string if not enabled.
local function from_style(t)
  if not enabled then return '' end
  local seq = ''
  for k, v in pairs(t) do
    local c = codes[k] ; if c and v then seq = seq .. ';' .. c end
  end
  local c = codes[t.fg] if c then seq = seq .. ';' .. c end
  c = codes[t.bg] if c then seq = seq .. ';' .. c + 10 end
  return '\27[0'..seq..'m'
end

------------------------------------------------------------------------------
-- Module Table
------------------------------------------------------------------------------

local M = {
  encode = encode,
  ESC = ESC,
  esc = esc,
  from_style = from_style,
  set_enabled = set_enabled,
}

return M
