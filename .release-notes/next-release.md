## Update ponylang/ssl dependency to 1.0.1

We've updated the ponylang/ssl library dependency in this project to 1.0.1

## Remove lifecycle event receiver chaining

The `_next_lifecycle_event_receiver()` / `_on_send()` / `_on_expect_set()` approach has been removed.

### Non-SSL connections

Remove `_next_lifecycle_event_receiver()` from your actors. No other changes needed.

Before:

```pony
actor MyServer is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()

  new create(auth: TCPServerAuth, fd: U32) =>
    _tcp_connection = TCPConnection.server(auth, fd, this, this)

  fun ref _connection(): TCPConnection => _tcp_connection
  fun ref _next_lifecycle_event_receiver(): None => None

  fun ref _on_received(data: Array[U8] iso) =>
    _connection().send(consume data)
```

After:

```pony
actor MyServer is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()

  new create(auth: TCPServerAuth, fd: U32) =>
    _tcp_connection = TCPConnection.server(auth, fd, this, this)

  fun ref _connection(): TCPConnection => _tcp_connection

  fun ref _on_received(data: Array[U8] iso) =>
    _connection().send(consume data)
```

### SSL connections

See "Redesign SSL connection API" below.

## Redesign SSL connection API

`TCPConnection` now has four constructors: `client`, `server`, `ssl_client`, and `ssl_server`. Replace `NetSSLClientConnection` / `NetSSLServerConnection` lifecycle wrappers with the new `ssl_client` / `ssl_server` constructors. These constructors take `SSLContext val` and handle SSL session creation internally.

Before:

```pony
actor MySSLServer is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()

  new create(auth: TCPServerAuth, ssl: SSL iso, fd: U32) =>
    let sslc = NetSSLServerConnection(consume ssl, this)
    _tcp_connection = TCPConnection.server(auth, fd, this, sslc)

  fun ref _connection(): TCPConnection => _tcp_connection
  fun ref _next_lifecycle_event_receiver(): None => None
```

After:

```pony
actor MySSLServer is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()

  new create(auth: TCPServerAuth, sslctx: SSLContext val, fd: U32) =>
    _tcp_connection = TCPConnection.ssl_server(auth, sslctx, fd, this, this)

  fun ref _connection(): TCPConnection => _tcp_connection
```

For clients, the equivalent is:

```pony
_tcp_connection = TCPConnection.ssl_client(
  auth, sslctx, host, port, from, this, this)
```

`ssl_client` and `ssl_server` are non-partial. If SSL session creation fails, the failure is reported asynchronously via `_on_connection_failure()` (clients) or `_on_start_failure()` (servers).

## Redesign send system for fallible sends and completion tracking

### Fallible send

`send()` now returns `(SendToken | SendError)` instead of silently accepting data. On failure, a `SendError` tells you why:

- `SendErrorNotConnected` — connection not open (permanent)
- `SendErrorNotWriteable` — socket under backpressure (wait for `_on_unthrottled`)

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
end
```

### Send completion tracking

On success, `send()` returns a `SendToken` that is later delivered to the new `_on_sent(token)` callback when the data has been fully handed to the OS. Implement `_on_sent` on your lifecycle event receiver to track completion:

```pony
fun ref _on_sent(token: SendToken) =>
  // Data identified by token has been fully handed to the OS
```

## Add send failure notification

`_on_send_failed(token)` is a new callback on both `ServerLifecycleEventReceiver` and `ClientLifecycleEventReceiver`. It fires when a previously accepted `send()` could not be delivered to the OS — specifically when the connection closes while a partial write is still pending. The token matches the one returned by `send()`.

```pony
fun ref _on_send_failed(token: SendToken) =>
  // The send identified by token was accepted but never delivered
```

The default implementation is a no-op. If the connection closes with no pending partial write, `_on_send_failed` does not fire — `_on_closed` alone signals that the connection is gone.

## Add server start failure notification

`_on_start_failure()` is a new callback on `ServerLifecycleEventReceiver`. It fires when a server connection fails before `_on_started` would have been delivered — for example, when an SSL handshake fails. This parallels `_on_connection_failure()` on the client side.

```pony
fun ref _on_start_failure() =>
  // Server connection failed before it was ready for application data
```

The default implementation is a no-op.
## Fix premature _on_unthrottled during Happy Eyeballs connect

When a client connection succeeded via Happy Eyeballs and the application sent data in `_on_connected` that triggered backpressure (partial write), `_on_unthrottled` was delivered immediately even though the socket was still not writeable and pending data remained unsent. Subsequent `send()` calls would return `SendErrorNotWriteable` despite the application having just been told backpressure was released.

The connection recovers when the next writeable event fires and drains the pending data, but no second `_on_unthrottled` is delivered since the throttle flag was already cleared.

Workaround for older versions: defer sends from `_on_connected` to a subsequent behavior turn so backpressure goes through the normal event path.

