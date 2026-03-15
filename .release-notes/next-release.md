## Add configurable read buffer size

TCPConnection now accepts a `read_buffer_size` constructor parameter (default 16KB) to set the initial buffer allocation and shrink-back minimum. The parameter takes a `ReadBufferSize` constrained type that guarantees a value of at least 1. Two new runtime methods let you tune the buffer after construction:

- `set_read_buffer_minimum(size)` — sets the floor the buffer shrinks to when empty
- `resize_read_buffer(size)` — forces the buffer to an exact size, reallocating immediately

```pony
match MakeReadBufferSize(128)
| let rbs: ReadBufferSize =>
  _tcp_connection = TCPConnection.server(auth, fd, this, this
    where read_buffer_size = rbs)
end

// Later, switch to a larger buffer for bulk transfer
match MakeReadBufferSize(8192)
| let rbs: ReadBufferSize =>
  _tcp_connection.set_read_buffer_minimum(rbs)
  _tcp_connection.resize_read_buffer(rbs)
end
```

The invariant chain `expect <= read_buffer_min <= read_buffer_size` is enforced by all three APIs. Each returns a result type indicating success or the specific constraint violation.

## Change expect() to return ExpectResult instead of raising an error

`expect()` previously raised an error when the requested value exceeded the buffer size. It now returns `ExpectResult`, which is either `ExpectSet` or `ExpectAboveBufferMinimum`. This is a breaking change — all callers using `try expect()? end` must switch to matching on the result.

Before:

```pony
try _tcp_connection.expect(4)? end
```

After:

```pony
match MakeExpect(4)
| let e: Expect => _tcp_connection.expect(e)
end
```

The guard now checks against the read buffer minimum rather than the buffer size, enforcing the `expect <= read_buffer_min` invariant.
## Make expect() use a constrained type instead of raw USize

`expect()` now takes `(Expect | None)` instead of `USize`. `Expect` is a constrained type that guarantees a value of at least 1. `None` replaces the magic value `0` to mean "deliver all available data." This follows the same pattern used by `IdleTimeout`, `ReadBufferSize`, and `MaxSpawn`.

Before:

```pony
_tcp_connection.expect(4)
_tcp_connection.expect(0)
```

After:

```pony
match MakeExpect(4)
| let e: Expect => _tcp_connection.expect(e)
end
_tcp_connection.expect(None)
```

## Add TCP_NODELAY and socket buffer size methods

TCPConnection now exposes five methods for commonly-tuned socket options on connected sockets:

- `set_nodelay(state)` — enable/disable Nagle's algorithm (TCP_NODELAY)
- `set_so_rcvbuf(bufsize)` / `get_so_rcvbuf()` — set/get the OS receive buffer size
- `set_so_sndbuf(bufsize)` / `get_so_sndbuf()` — set/get the OS send buffer size

All setters return 0 on success or a non-zero errno on failure. Getters return `(errno, value)`. All methods require a connected socket — they return a non-zero error indicator when the connection is not open.

```pony
fun ref _on_started() =>
  _tcp_connection.set_nodelay(true)
  _tcp_connection.set_so_rcvbuf(65536)
  _tcp_connection.set_so_sndbuf(65536)

  (let errno: U32, let rcvbuf: U32) = _tcp_connection.get_so_rcvbuf()
```

## Add general socket option access

TCPConnection now exposes general-purpose `getsockopt`/`setsockopt` methods for accessing any socket option, not just the ones with dedicated convenience methods:

- `getsockopt(level, option_name, option_max_size)` — raw bytes interface to `getsockopt(2)`
- `getsockopt_u32(level, option_name)` — convenience wrapper when the option value is a `U32`
- `setsockopt(level, option_name, option)` — raw bytes interface to `setsockopt(2)`
- `setsockopt_u32(level, option_name, option)` — convenience wrapper when the option value is a `U32`

All methods require a connected socket and return errno-based results matching the existing convenience methods. Use `OSSockOpt` constants for the `level` and `option_name` parameters.

```pony
// Set TCP_KEEPIDLE via the general-purpose interface
_tcp_connection.setsockopt_u32(
  OSSockOpt.ipproto_tcp(), OSSockOpt.tcp_keepidle(), 60)

// Read back a socket option as raw bytes
(let errno: U32, let data: Array[U8] iso) =
  _tcp_connection.getsockopt(
    OSSockOpt.sol_socket(), OSSockOpt.so_rcvbuf())
```

For commonly-tuned options (TCP_NODELAY, SO_RCVBUF, SO_SNDBUF), the dedicated convenience methods remain the preferred interface.

## Fix dispose() hanging when peer FIN is missed

`TCPConnectionActor.dispose()` previously called `close()`, which does a graceful half-close — it sends a FIN and waits for the peer to acknowledge before fully cleaning up. On POSIX with edge-triggered oneshot events, the peer's FIN notification can be missed in a narrow timing window after resubscription, leaving the socket stuck in CLOSE_WAIT and preventing the runtime from exiting.

`dispose()` now calls `hard_close()`, which immediately unsubscribes from ASIO, closes the fd, and fires `_on_closed()`. This matches what callers expect from disposal: unconditional teardown, not a protocol exchange. Applications that need a graceful close should call `close()` explicitly before disposal.

