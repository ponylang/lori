## Add general-purpose one-shot timer

`set_timer()` creates a one-shot timer on a connection that fires `_on_timer()` after a configured duration. Unlike `idle_timeout()`, this timer fires unconditionally — it is not reset by send/receive activity. This is the building block for application-level timeouts like query deadlines where I/O activity should not postpone the timeout.

```pony
fun ref _on_connected() =>
  _tcp_connection.send("SELECT * FROM big_table")
  match MakeTimerDuration(10_000)
  | let d: TimerDuration =>
    match _tcp_connection.set_timer(d)
    | let t: TimerToken => _query_timer = t
    end
  end

fun ref _on_received(data: Array[U8] iso) =>
  match _query_timer
  | let t: TimerToken =>
    _tcp_connection.cancel_timer(t)
    _query_timer = None
  end
  // process response...

fun ref _on_timer(token: TimerToken) =>
  // query timed out
  _tcp_connection.close()
```

Only one timer can be active at a time. Setting a timer while one is active returns `SetTimerAlreadyActive` — cancel the existing timer first. The timer survives `close()` (graceful shutdown) but is cancelled by `hard_close()`. There is no automatic re-arming; call `set_timer()` again from `_on_timer()` for repetition.
