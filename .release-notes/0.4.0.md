## Make Lori callbacks private

All the callbacks on `TCPClientActor`, `TCPServerActor`, and `TCPConnectionActor` have been changed to private from public. This better indicates that the methods are not intended to be called from outside of Lori. To update, you'll need to make the methods on your objects that implement any of the above traits private as well.

## Rename `_on_failure` callbacks

`_on_failure` is very generic and doesn't state what the failure was. When someone is using lori, they will have an `_on_failure` callback that could be any number of failures for that actor. Switching the name to something more specific should make it considerably more clear.

- `_on_failure` for `TCPListenerActor` has been renamed `_on_listen_failure`.
- `_on_failure` for `TCPClientActor` has been renamed `_on_connection_failure`.

Adjusting to this change is as simple as finding any usage you had of `_on_failure` and replacing it with `_on_connection_failure` or `_on_listen_failure` as appropriate.
