local scope = ...
scope.pi = 3.14
scope.path = scope:get_list'PATH'
scope:insert('list', 'd')
scope:insert('list', 'A', 1)
