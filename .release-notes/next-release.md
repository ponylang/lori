## Update ponylang/ssl dependency to 1.0.1

We've updated the ponylang/ssl library dependency in this project to 1.0.1

## Separate data interception from lifecycle events

Protocol-level data transformation (encryption, compression, etc.) is now handled by the new `DataInterceptor` trait instead of lifecycle event receiver chaining. This replaces the `_next_lifecycle_event_receiver()` / `_on_send()` / `_on_expect_set()` approach which couldn't correctly compose multiple protocol layers.

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

Replace `NetSSLClientConnection` / `NetSSLServerConnection` lifecycle wrappers with `SSLClientInterceptor` / `SSLServerInterceptor` passed as a parameter to `TCPConnection.client()` / `TCPConnection.server()`.

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

  new create(auth: TCPServerAuth, ssl: SSL iso, fd: U32) =>
    let interceptor = SSLServerInterceptor(consume ssl)
    _tcp_connection = TCPConnection.server(auth, fd, this, this, interceptor)

  fun ref _connection(): TCPConnection => _tcp_connection
```

### Custom protocol layers

If you implemented custom protocol handling via `_next_lifecycle_event_receiver()` chaining, implement the `DataInterceptor` trait instead. See the `DataInterceptor` docstring for the full API.

## Redesign send system for fallible sends and completion tracking

### Fallible send

`send()` now returns `(SendToken | SendError)` instead of silently accepting data. On failure, a `SendError` tells you why:

- `SendErrorNotConnected` — connection not open (permanent)
- `SendErrorNotWriteable` — socket under backpressure (wait for `_on_unthrottled`)
- `SendErrorNotReady` — interceptor handshake in progress (wait for `_on_connected` / `_on_started`)

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
| let _: SendErrorNotReady =>
  // Interceptor handshake not complete
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

