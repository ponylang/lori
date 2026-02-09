## Redesign send system for fallible sends and completion tracking

### Fallible send

`send()` now returns `(SendToken | SendError)` instead of silently accepting data. On failure, a `SendError` tells you why:

- `SendErrorNotConnected` — connection not open (permanent)
- `SendErrorNotWriteable` — socket under backpressure (wait for `_on_unthrottled`)
- `SendErrorNotReady` — interceptor handshake in progress (wait for `_on_connected` / `_on_started`)

The library no longer queues data on the application's behalf during backpressure. When `send()` returns `SendErrorNotWriteable`, the application decides what to do — queue the data, drop it, or close the connection.

`is_writeable()` lets you check whether the connection can accept a `send()` call before attempting one.

Existing code that calls `send()` as a fire-and-forget statement still compiles — Pony allows discarding return values. To take advantage of the new API:

```pony
match _tcp_connection.send(data)
| let token: SendToken =>
  // Data accepted; _on_sent(token) fires when handed to OS
  None
| let _: SendErrorNotConnected =>
  // Connection is down
  None
| let _: SendErrorNotWriteable =>
  // Backpressured; queue or drop (your decision)
  None
| let _: SendErrorNotReady =>
  // Interceptor handshake not complete
  None
end
```

### Send completion tracking

On success, `send()` returns a `SendToken` that is later delivered to the new `_on_sent(token)` callback when the data has been fully handed to the OS. Implement `_on_sent` on your lifecycle event receiver to track completion:

```pony
fun ref _on_sent(token: SendToken) =>
  // Data identified by token has been fully handed to the OS
```
