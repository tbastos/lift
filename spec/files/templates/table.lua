{
{%
  -- traverse table in sorted order
  local keys = {}
  for k in pairs(t) do keys[#keys+1] = k end
  table.sort(keys)
  for i, k in ipairs(keys) do
%}
  {! 'row.lua' !! {k = k, v = t[k]} !},
{% end %}
}
