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

