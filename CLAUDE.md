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
  lori.pony                 -- Package docstring (entry point for API documentation)
  tcp_connection.pony       -- TCPConnection class (core: read/write/connect/close/SSL)
  tcp_connection_actor.pony -- TCPConnectionActor trait (actor wrapper)
  tcp_listener.pony         -- TCPListener class (accept loop, connection limits)
  tcp_listener_actor.pony   -- TCPListenerActor trait (actor wrapper)
  lifecycle_event_receiver.pony -- Client/ServerLifecycleEventReceiver traits
  send_token.pony           -- SendToken class, SendError primitives and type alias
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

1. **`TCPConnection`** (class) — All TCP state and I/O logic including SSL. Created with `TCPConnection.client(...)`, `TCPConnection.server(...)`, `TCPConnection.ssl_client(...)`, or `TCPConnection.ssl_server(...)`. Not an actor itself.
2. **`TCPConnectionActor`** (trait) — The actor trait users implement. Requires `fun ref _connection(): TCPConnection`. Provides behaviors that delegate to the TCPConnection: `_event_notify`, `_read_again`, `dispose`, etc.
3. **Lifecycle event receivers** — `ClientLifecycleEventReceiver` (callbacks: `_on_connected`, `_on_connecting`, `_on_connection_failure`, `_on_received`, `_on_closed`, `_on_sent`, `_on_send_failed`, etc.) and `ServerLifecycleEventReceiver` (callbacks: `_on_started`, `_on_start_failure`, `_on_received`, `_on_closed`, `_on_sent`, `_on_send_failed`, etc.). Both share common callbacks like `_on_received`, `_on_closed`, `_on_throttled`/`_on_unthrottled`, `_on_sent`, `_on_send_failed`.

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

Use the `ssl_client` or `ssl_server` constructors with an `SSLContext val`:

```
actor MySSLServer is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()

  new create(auth: TCPServerAuth, sslctx: SSLContext val, fd: U32) =>
    _tcp_connection = TCPConnection.ssl_server(auth, sslctx, fd, this, this)

  fun ref _connection(): TCPConnection => _tcp_connection
```

```
actor MySSLClient is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()

  new create(auth: TCPConnectAuth, sslctx: SSLContext val,
    host: String, port: String)
  =>
    _tcp_connection = TCPConnection.ssl_client(auth, sslctx, host, port, "",
      this, this)

  fun ref _connection(): TCPConnection => _tcp_connection

  fun ref _on_connected() => // SSL handshake complete, ready for data
```

SSL is handled internally by `TCPConnection`. The `ssl_client`/`ssl_server` constructors create an `SSL` session from the provided `SSLContext val`, perform the handshake transparently, and deliver `_on_connected`/`_on_started` only after the handshake completes. If SSL session creation fails, `_on_connection_failure()` (client) or `_on_start_failure()` (server) fires asynchronously. If the handshake fails, `hard_close()` triggers the same failure callbacks.

### SSL internals

SSL state lives directly in `TCPConnection` (fields `_ssl`, `_ssl_ready`, `_ssl_failed`, `_ssl_expect`). Key behaviors:

- **0-to-N output per input on both sides:** Both read and write can produce zero, one, or many output chunks per input chunk. During handshake, output may be zero (buffered). A single TCP read containing multiple SSL records produces multiple decrypted chunks.
- **`_ssl_poll()` pump:** Called after `ssl.receive()` in `_deliver_received()`. Checks SSL state, delivers decrypted data to the lifecycle event receiver, and flushes encrypted protocol data (handshake responses, etc.) via `_ssl_flush_sends()`.
- **Client handshake initiation:** When TCP connects, `_ssl_flush_sends()` sends the ClientHello. The handshake proceeds via `_deliver_received()` → `ssl.receive()` → `_ssl_poll()`.
- **Ready signaling:** `_ssl_ready` is set when `ssl.state()` returns `SSLReady`, which triggers `_on_connected`/`_on_started` delivery.
- **Error handling:** `SSLAuthFail` or `SSLError` states trigger `hard_close()`. If the handshake never completed, clients get `_on_connection_failure()` and servers get `_on_start_failure()`.
- **Expect handling:** The application's `expect()` value is stored in `_ssl_expect` and used when chunking decrypted data via `ssl.read()`. The TCP read layer uses 0 (read all available) since SSL record framing doesn't align with application framing.

### Send system

`send()` is fallible — it returns `(SendToken | SendError)` instead of silently dropping data:

- `SendToken` — opaque token identifying the send operation. Delivered to `_on_sent(token)` when data is fully handed to the OS.
- `SendErrorNotConnected` — connection not open (permanent).
- `SendErrorNotWriteable` — socket under backpressure (transient, wait for `_on_unthrottled`).
During SSL handshake (before `_on_connected`/`_on_started`), `send()` returns `SendErrorNotConnected`.

`is_writeable()` lets the application check writeability before calling `send()`.

`_on_sent(token)` always fires in a subsequent behavior turn (via `_notify_sent` on `TCPConnectionActor`), never synchronously during `send()`. If the connection closes with a pending partial write, `_on_send_failed(token)` fires (via `_notify_send_failed`) to notify the application that the accepted send could not be delivered. `_on_send_failed` always arrives after `_on_closed`, which fires synchronously during `hard_close()`.

The library does not queue data on behalf of the application during backpressure. `send()` returns `SendErrorNotWriteable` and the application decides what to do (queue, drop, close, etc.).

Design: Discussion #150.

### Platform differences

POSIX and Windows (IOCP) have distinct code paths throughout `TCPConnection`, guarded by `ifdef posix`/`ifdef windows`. POSIX uses edge-triggered oneshot events with resubscription; Windows uses IOCP completion callbacks.

## Future Work

- **TCPConnection refactoring**: `tcp_connection.pony` has multiple interleaved state machines encoded as boolean flags (`_connected`, `_closed`, `_shutdown`, `_shutdown_peer`, `_ssl_ready`, `_ssl_failed`, `_throttled`, `_readable`, `_writeable`, `_muted`). Valid state combinations aren't obvious and invalid combinations aren't prevented. `_event_notify` is particularly dense — it handles own-event vs Happy Eyeballs events with nested platform and SSL branching. Potential improvements: explicit state types instead of boolean flags, breaking `_event_notify` into smaller dispatch methods, grouping platform-specific paths. Pony's reference capabilities may constrain sub-object extraction.


## Conventions

- Follows the [Pony standard library Style Guide](https://github.com/ponylang/ponyc/blob/main/STYLE_GUIDE.md)
- `_Unreachable()` primitive used for states the compiler can't prove impossible — prints location and exits with code 1
- `TCPConnection.none()` used as a field initializer before real initialization happens via `_finish_initialization` behavior
- Auth hierarchy: `AmbientAuth` > `NetAuth` > `TCPAuth` > `TCPListenAuth` > `TCPServerAuth`, with `TCPConnectAuth` as a separate leaf under `TCPAuth`
- Core lifecycle callbacks are prefixed with `_on_` (private by convention)
- Tests use hardcoded ports per test
- `\nodoc\` annotation on test classes
