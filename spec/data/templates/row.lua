{{k}} = {% local tp = type(v) %}
{% if tp == 'table' then %}{( 'table.lua' << {t = v} )}
{% elseif tp == 'string' then %}'{{v}}'
{% elseif tp == 'number' then %}{{v}}
{% elseif tp == 'boolean' then %}{{v and 'true' or 'false'}}
{% else error('unsupported type') end %}
