pi = {{ tostring(math.pi):sub(1,6) }}
{# Use templates to pretty print an acyclic table #}
{( 'table.lua' << {t = {a = 1, b = true, c = {d = 'e'}}} )}
