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
