## Require explicit connection-failure handling for client connections

`ClientLifecycleEventReceiver` no longer provides a default for `_on_connection_failure`. Every implementor must now provide an explicit method body.

Before:

```pony
actor MyClient is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()

  fun ref _connection(): TCPConnection =>
    _tcp_connection
```

After:

```pony
actor MyClient is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connection_failure(reason: ConnectionFailureReason) =>
    None
```
