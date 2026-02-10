## Add send failure notification

`_on_send_failed(token)` is a new callback on both `ServerLifecycleEventReceiver` and `ClientLifecycleEventReceiver`. It fires when a previously accepted `send()` could not be delivered to the OS — specifically when the connection closes while a partial write is still pending. The token matches the one returned by `send()`.

```pony
fun ref _on_send_failed(token: SendToken) =>
  // The send identified by token was accepted but never delivered
```

The default implementation is a no-op. If the connection closes with no pending partial write, `_on_send_failed` does not fire — `_on_closed` alone signals that the connection is gone.
