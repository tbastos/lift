This template file contains invalid Lua code
<nav class="sidebar">
  <ul class="nav-groups">
{% for i, n in ipairs({2, 4}) do %}
    <li class="nav-group-name">
      {:i:} * 2 = {:n:}
      <ul class="nav-group-tasks">
{%   for x, y in do %}
      {:x:} + {:y:}
{%   end %}
      </ul>
  </li>
{% end %}
  </ul>
</nav>

