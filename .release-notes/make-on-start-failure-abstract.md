## Require explicit start-failure handling for server connections

`ServerLifecycleEventReceiver` and `ServerTCPConnectionNotify` no longer provide a default for start-failure handling. Every implementor must now provide an explicit method body.

Native API — before:

```pony
actor MyServer is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()

  fun ref _connection(): TCPConnection =>
    _tcp_connection
```

Native API — after:

```pony
actor MyServer is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_start_failure(reason: StartFailureReason) =>
    None
```

Notifier API — before:

```pony
class MyNotify is ServerTCPConnectionNotify
  fun ref on_received(conn: ServerTCPConnection ref, data: Array[U8] iso):
    ReadAction
  =>
    KeepReading
```

Notifier API — after:

```pony
class MyNotify is ServerTCPConnectionNotify
  fun ref on_start_failure(conn: ServerTCPConnection ref,
    reason: StartFailureReason)
  =>
    None

  fun ref on_received(conn: ServerTCPConnection ref, data: Array[U8] iso):
    ReadAction
  =>
    KeepReading
```
