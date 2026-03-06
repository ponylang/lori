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
_tcp_connection.expect(4)
```

The guard now checks against the read buffer minimum rather than the buffer size, enforcing the `expect <= read_buffer_min` invariant.
