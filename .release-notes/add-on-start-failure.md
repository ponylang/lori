## Add server start failure notification

`_on_start_failure()` is a new callback on `ServerLifecycleEventReceiver`. It fires when a server connection fails before `_on_started` would have been delivered — for example, when an SSL handshake fails. This parallels `_on_connection_failure()` on the client side.

```pony
fun ref _on_start_failure() =>
  // Server connection failed before it was ready for application data
```

The default implementation is a no-op.
