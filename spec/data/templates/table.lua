{
{% for k, v in pairs(t) do %}
  {( 'row.lua' << {k = k, v = v} )}
{% end %}
}
