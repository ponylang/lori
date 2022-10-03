## Rename `on_failure` callback to `on_connection_failure`

`on_failure` is very generic and doesn't state what the failure was. When someone is using lori, they will have an `on_failure` callback that could be any number of failures for that actor. Switching the name to `on_connection_failure` should make it considerably more clear.

Adjusting to this change is as simple as finding any usage you had of `of_failure` and replacing it with `on_connection_failure`.

