## Make _on_start_failure abstract

`ServerLifecycleEventReceiver._on_start_failure` no longer has a default body. Every type that implements `ServerLifecycleEventReceiver` must now provide the method. The compiler enforces this at build time.

The previous default silently discarded server-side SSL handshake failures. A failed handshake meant no `_on_started`, no `_on_closed`, no error — the connection simply vanished. Making the method abstract forces the application to handle the failure.

Actors that do not use SSL will never receive the callback, but still must provide a body:

Before (compiled, silently ignored failures):

```pony
actor MyServer is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()

  fun ref _connection(): TCPConnection =>
    _tcp_connection
```

After:

```pony
actor MyServer is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_start_failure(reason: StartFailureReason) => None
```
