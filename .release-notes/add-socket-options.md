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
