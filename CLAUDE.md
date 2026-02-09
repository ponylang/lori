# Lori

A Pony TCP networking library. Reimagines the standard library's `net` package with a different design: the connection logic lives in a plain `class` (`TCPConnection`/`TCPListener`) that the user's `actor` delegates to, rather than baking everything into a single actor.

## Building and Testing

```
make ssl=3.0.x              # build + run unit tests
make test ssl=3.0.x          # same (test is the default)
make ci ssl=3.0.x            # unit tests + build examples + build stress tests
make examples ssl=3.0.x      # build all examples
make stress-tests ssl=3.0.x  # build stress tests
make clean                   # clean build artifacts + corral deps
make config=debug ssl=3.0.x  # debug build
```

**SSL version is required** for all build/test targets. This machine has OpenSSL 3.x, so use `ssl=3.0.x`.

Uses `corral` for dependency management. `make` automatically runs `corral fetch` before compiling.

## Dependencies

- `github.com/ponylang/ssl.git` — SSL/TLS support
- `github.com/ponylang/logger.git` — Logging

## Source Layout

```
lori/
  tcp_connection.pony       -- TCPConnection class (core: read/write/connect/close)
  tcp_connection_actor.pony -- TCPConnectionActor trait (actor wrapper)
  tcp_listener.pony         -- TCPListener class (accept loop, connection limits)
  tcp_listener_actor.pony   -- TCPListenerActor trait (actor wrapper)
  lifecycle_event_receiver.pony -- Client/ServerLifecycleEventReceiver traits
  data_interceptor.pony     -- DataInterceptor trait, WireSender/IncomingDataReceiver/InterceptorControl interfaces
  send_token.pony           -- SendToken class, SendError primitives and type alias
  net_ssl_connection.pony   -- SSLClientInterceptor/SSLServerInterceptor (SSL layer)
  auth.pony                 -- Auth primitives (NetAuth, TCPAuth, TCPListenAuth, etc.)
  pony_tcp.pony             -- FFI wrappers for pony_os_* TCP functions
  pony_asio.pony            -- FFI wrappers for pony_asio_event_* functions
  ossocket.pony             -- _OSSocket: getsockopt/setsockopt wrappers
  ossocketopt.pony          -- OSSockOpt: socket option constants (large, generated)
  _panics.pony              -- _Unreachable primitive for impossible states
  _test.pony                -- Tests
examples/
  echo-server/              -- Simple echo server
  infinite-ping-pong/       -- Ping-pong client+server
  net-ssl-echo-server/      -- SSL echo server
  net-ssl-infinite-ping-pong/ -- SSL ping-pong
stress-tests/
  open-close/               -- Connection open/close stress test
```

## Architecture

### Core Design Pattern

Lori separates connection logic (class) from actor scheduling (trait):

1. **`TCPConnection`** (class) — All TCP state and I/O logic. Created with `TCPConnection.client(...)` or `TCPConnection.server(...)`. Not an actor itself.
2. **`TCPConnectionActor`** (trait) — The actor trait users implement. Requires `fun ref _connection(): TCPConnection`. Provides behaviors that delegate to the TCPConnection: `_event_notify`, `_read_again`, `dispose`, etc.
3. **Lifecycle event receivers** — `ClientLifecycleEventReceiver` (callbacks: `_on_connected`, `_on_connecting`, `_on_connection_failure`, `_on_received`, `_on_closed`, `_on_sent`, etc.) and `ServerLifecycleEventReceiver` (callbacks: `_on_started`, `_on_received`, `_on_closed`, `_on_sent`, etc.). Both share common callbacks like `_on_received`, `_on_closed`, `_on_throttled`/`_on_unthrottled`, `_on_sent`.
4. **Data interceptors** — `DataInterceptor` trait for protocol-level data transformation (encryption, compression). Interceptors sit between `TCPConnection` and the lifecycle event receiver, transforming data in both directions. Passed as an optional parameter to `TCPConnection.client()` / `TCPConnection.server()`.

### How to implement a server

```
actor MyServer is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()

  new create(auth: TCPServerAuth, fd: U32) =>
    _tcp_connection = TCPConnection.server(auth, fd, this, this)

  fun ref _connection(): TCPConnection => _tcp_connection

  fun ref _on_received(data: Array[U8] iso) =>
    // handle data
```

### How to implement a client

```
actor MyClient is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()

  new create(auth: TCPConnectAuth, host: String, port: String) =>
    _tcp_connection = TCPConnection.client(auth, host, port, "", this, this)

  fun ref _connection(): TCPConnection => _tcp_connection

  fun ref _on_connected() => // connected
  fun ref _on_received(data: Array[U8] iso) => // handle data
```

### How to add SSL

Pass an `SSLClientInterceptor` or `SSLServerInterceptor` as the interceptor parameter:

```
actor MySSLServer is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()

  new create(auth: TCPServerAuth, ssl: SSL iso, fd: U32) =>
    let interceptor = SSLServerInterceptor(consume ssl)
    _tcp_connection = TCPConnection.server(auth, fd, this, this, interceptor)

  fun ref _connection(): TCPConnection => _tcp_connection
```

### Data interceptors

The `DataInterceptor` trait separates protocol-level data transformation from application lifecycle callbacks. Interceptors transform data in both directions (incoming and outgoing) and are passed as an optional parameter to `TCPConnection.client()` / `TCPConnection.server()`.

Key points:
- `on_setup(control)` is called when the connection is established. Call `control.signal_ready()` when the interceptor is ready (e.g., after SSL handshake completes). `TCPConnection` defers `_on_connected`/`_on_started` until the interceptor signals ready.
- `incoming(data, receiver, wire)` transforms incoming data and pushes results to `receiver.receive()`. Can also send protocol data (e.g., handshake responses) via `wire.send()`.
- `outgoing(data, wire)` transforms outgoing data and pushes results to `wire.send()`.
- `on_teardown()` is called on connection close.
- All methods have default pass-through implementations.
- If the connection closes before the interceptor signals ready, clients get `_on_connection_failure()`.

### Send system

`send()` is fallible — it returns `(SendToken | SendError)` instead of silently dropping data:

- `SendToken` — opaque token identifying the send operation. Delivered to `_on_sent(token)` when data is fully handed to the OS.
- `SendErrorNotConnected` — connection not open (permanent).
- `SendErrorNotWriteable` — socket under backpressure (transient, wait for `_on_unthrottled`).
- `SendErrorNotReady` — interceptor handshake not complete (transient, wait for `_on_connected`/`_on_started`).

`is_writeable()` lets the application check writeability before calling `send()`.

`_on_sent(token)` always fires in a subsequent behavior turn (via `_notify_sent` on `TCPConnectionActor`), never synchronously during `send()`. If the connection closes with a pending send, `_on_sent` does not fire — `_on_closed` is the signal that outstanding tokens are implicitly failed.

The library does not queue data on behalf of the application during backpressure. `send()` returns `SendErrorNotWriteable` and the application decides what to do (queue, drop, close, etc.).

Design: Discussion #150.

### SSL interceptor internals

The SSL interceptors (`SSLClientInterceptor`/`SSLServerInterceptor` in `net_ssl_connection.pony`) implement `DataInterceptor` for SSL/TLS encryption. Key behaviors:

- **0-to-N output per input on both sides:** Both read and write can produce zero, one, or many output chunks per input chunk. During handshake, output may be zero (buffered). A single TCP read containing multiple SSL records produces multiple decrypted chunks.
- **Unified `_ssl_poll()` pump:** Called from `incoming()`. It delivers decrypted data to the `IncomingDataReceiver` AND sends encrypted protocol data (handshake responses, etc.) via the `WireSender`.
- **`on_setup()` flushes initial SSL data:** For clients, this sends the ClientHello to initiate the handshake. For servers, it flushes any initial protocol data the SSL library has ready.
- **Ready signaling:** `control.signal_ready()` is called when the SSL handshake completes, which triggers `_on_connected`/`_on_started` delivery to the application.
- **Error handling:** SSL auth failures or errors call `control.close()`, which closes the connection. If the handshake never completed, clients get `_on_connection_failure()`.

The old lifecycle receiver chaining approach (issue #137) was replaced by the interceptor design (Discussion #149). Composition of multiple interceptors (`ChainedInterceptor`) is deferred to a follow-up.

### Platform differences

POSIX and Windows (IOCP) have distinct code paths throughout `TCPConnection`, guarded by `ifdef posix`/`ifdef windows`. POSIX uses edge-triggered oneshot events with resubscription; Windows uses IOCP completion callbacks.

## Conventions

- Follows the [Pony standard library Style Guide](https://github.com/ponylang/ponyc/blob/main/STYLE_GUIDE.md)
- `_Unreachable()` primitive used for states the compiler can't prove impossible — prints location and exits with code 1
- `TCPConnection.none()` used as a field initializer before real initialization happens via `_finish_initialization` behavior
- Auth hierarchy: `AmbientAuth` > `NetAuth` > `TCPAuth` > `TCPListenAuth` > `TCPServerAuth`, with `TCPConnectAuth` as a separate leaf under `TCPAuth`
- Core lifecycle callbacks are prefixed with `_on_` (private by convention); SSL-specific callbacks on `NetSSLLifecycleEventReceiver` use public `on_` prefix
- Tests use hardcoded ports per test
- `\nodoc\` annotation on test classes
