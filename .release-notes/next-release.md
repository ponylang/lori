## Add per-connection idle timeout

`idle_timeout()` sets a per-connection timer that fires `_on_idle_timeout()` when no data is sent or received for the configured duration. The duration is an `IdleTimeout` constrained type (constructed via `MakeIdleTimeout`) that guarantees a non-zero millisecond value. The timer resets on every successful `send()` and every received data event, and automatically re-arms after each firing.

```pony
fun ref _on_started() =>
  match MakeIdleTimeout(30_000) // 30 seconds
  | let t: IdleTimeout =>
    _tcp_connection.idle_timeout(t)
  end

fun ref _on_idle_timeout() =>
  _tcp_connection.close()
```

Uses a per-connection ASIO timer event — no extra actors or shared state needed. Call `idle_timeout(None)` to disable.

