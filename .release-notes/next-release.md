## Fix accept loop spinning on persistent errors

Previously, when `TCPListener`'s accept loop encountered a non-EWOULDBLOCK error (such as running out of file descriptors), it would retry immediately in a tight loop. Since persistent errors like EMFILE never resolve on their own, this caused the listener to spin indefinitely, consuming CPU without making progress.

The accept loop now exits on any error, letting the ASIO event system re-notify the listener. This gives other actors a chance to run and potentially free resources before the next accept attempt.

## Fix read loop not yielding after byte threshold

The POSIX read loop in `TCPConnection` was missing a `return` after scheduling a deferred `_read_again` when the byte threshold was reached. This meant the loop continued reading from the socket in the same behavior call indefinitely under sustained load, preventing per-actor GC from running (GC only runs between behavior invocations) and queuing redundant `_read_again` messages. The read loop now correctly exits after reaching the threshold, allowing GC and other actors to run before resuming.

## Add IPv4-only and IPv6-only support

Lori now supports restricting connections to a specific IP protocol version. Client constructors (`TCPConnection.client`, `TCPConnection.ssl_client`) and `TCPListener` accept an optional `ip_version` parameter that defaults to `DualStack` (existing behavior).

Pass `IP4` to restrict to IPv4 only or `IP6` for IPv6 only:

```pony
// IPv4-only listener
_tcp_listener = TCPListener(listen_auth, "127.0.0.1", "7669", this
  where ip_version = IP4)

// IPv4-only client
_tcp_connection = TCPConnection.client(auth, "127.0.0.1", "7669", "", this,
  this where ip_version = IP4)

// IPv6-only client
_tcp_connection = TCPConnection.client(auth, "::1", "7669", "", this, this
  where ip_version = IP6)

// SSL client with IPv4 only
_tcp_connection = TCPConnection.ssl_client(auth, sslctx, "127.0.0.1", "7669",
  "", this, this where ip_version = IP4)
```

Server-side constructors (`server`, `ssl_server`) don't need this parameter — they accept an already-connected fd whose protocol version was determined by the listener.

## Change TCPListener parameter order

The `ip_version` parameter on `TCPListener.create` now comes before `limit`. Since `ip_version` is a hard requirement in many environments while `limit` is rarely set, the more commonly used parameter should come first.

If you were passing `limit` positionally:

```pony
// Before
_tcp_listener = TCPListener(listen_auth, host, port, this, 100)

// After
match MakeMaxSpawn(100)
| let limit: MaxSpawn =>
  _tcp_listener = TCPListener(listen_auth, host, port, this where limit = limit)
end
```
