## Add optional connection timeout for client connections

Client connection attempts can now be bounded with a timeout that covers the TCP Happy Eyeballs phase and (for SSL connections) the TLS handshake. Pass a `ConnectionTimeout` to the `client` or `ssl_client` constructor:

```pony
match MakeConnectionTimeout(5_000)
| let ct: ConnectionTimeout =>
  _tcp_connection = TCPConnection.client(auth, host, port, "", this, this
    where connection_timeout = ct)
end
```

If the timeout fires before `_on_connected`, the connection fails with `ConnectionFailedTimeout` in `_on_connection_failure`. The timeout is disabled by default (`None`).

## Expand ConnectionFailureReason with ConnectionFailedTimeout

`ConnectionFailureReason` now includes `ConnectionFailedTimeout`. This is a breaking change — exhaustive matches on `ConnectionFailureReason` must add a branch for the new variant:

Before:

```pony
match reason
| ConnectionFailedDNS => // ...
| ConnectionFailedTCP => // ...
| ConnectionFailedSSL => // ...
end
```

After:

```pony
match reason
| ConnectionFailedDNS => // ...
| ConnectionFailedTCP => // ...
| ConnectionFailedSSL => // ...
| ConnectionFailedTimeout => // ...
end
```
## Fix idle timer issues with SSL connections

The idle timer had two issues with SSL connections:

The timer was being armed when the TCP connection established, before the SSL handshake completed. If an idle timeout was configured before the connection was ready, `_on_idle_timeout()` could fire before `_on_connected()` or `_on_started()`.

Calling `idle_timeout()` on an SSL connection during the handshake could also arm the timer prematurely, producing the same early `_on_idle_timeout()`. Additionally, when the handshake later completed, a second timer was created — leaking the first ASIO timer event.

The idle timer now defers arming until the SSL handshake completes, regardless of whether the timeout is configured before or during the handshake.

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

## Fix resource leak from orphaned Happy Eyeballs connections

When `close()` or `hard_close()` was called during the connecting phase, inflight Happy Eyeballs connection attempts could leak file descriptors and ASIO events. On Linux, failed connection attempts delivered error-only events (`ASIO_READ` without `ASIO_WRITE`) that were silently dropped by the writeable guard, preventing cleanup. On macOS, failed sockets produced two events per socket; the old guard accidentally filtered one, but the cleanup still had gaps.

Inflight connections are now reliably drained on all platforms.

