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

