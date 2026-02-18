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
  start_tls_error.pony      -- StartTLSError primitives and type alias
  auth.pony                 -- Auth primitives (NetAuth, TCPAuth, TCPListenAuth, etc.)
  pony_tcp.pony             -- FFI wrappers for pony_os_* TCP functions
  pony_asio.pony            -- FFI wrappers for pony_asio_event_* functions
  ossocket.pony             -- _OSSocket: getsockopt/setsockopt wrappers
  ossocketopt.pony          -- OSSockOpt: socket option constants (large, generated)
  _panics.pony              -- _Unreachable primitive for impossible states
  _test.pony                -- Tests
examples/
  backpressure/             -- Backpressure handling with throttle/unthrottle
  echo-server/              -- Simple echo server
  framed-protocol/          -- Length-prefixed framing with expect()
  infinite-ping-pong/       -- Ping-pong client+server
  net-ssl-echo-server/      -- SSL echo server
  net-ssl-infinite-ping-pong/ -- SSL ping-pong
  starttls-ping-pong/       -- STARTTLS upgrade from plaintext to TLS
stress-tests/
  open-close/               -- Connection open/close stress test
```

## Architecture

### Core Design Pattern

Lori separates connection logic (class) from actor scheduling (trait):

1. **`TCPConnection`** (class) — All TCP state and I/O logic including SSL. Created with `TCPConnection.client(...)`, `TCPConnection.server(...)`, `TCPConnection.ssl_client(...)`, or `TCPConnection.ssl_server(...)`. Existing plaintext connections can be upgraded to TLS via `start_tls()`. Not an actor itself.
2. **`TCPConnectionActor`** (trait) — The actor trait users implement. Requires `fun ref _connection(): TCPConnection`. Provides behaviors that delegate to the TCPConnection: `_event_notify`, `_read_again`, `dispose`, etc.
3. **Lifecycle event receivers** — `ClientLifecycleEventReceiver` (callbacks: `_on_connected`, `_on_connecting`, `_on_connection_failure`, `_on_received`, `_on_closed`, `_on_sent`, `_on_send_failed`, `_on_tls_ready`, `_on_tls_failure`, etc.) and `ServerLifecycleEventReceiver` (callbacks: `_on_started`, `_on_start_failure`, `_on_received`, `_on_closed`, `_on_sent`, `_on_send_failed`, `_on_tls_ready`, `_on_tls_failure`, etc.). Both share common callbacks like `_on_received`, `_on_closed`, `_on_throttled`/`_on_unthrottled`, `_on_sent`, `_on_send_failed`, `_on_tls_ready`, `_on_tls_failure`.

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

### TLS upgrade (STARTTLS)

`start_tls(ssl_ctx, host)` upgrades an established plaintext connection to TLS. It creates an SSL session, migrates expect state (`_ssl_expect = _expect; _expect = 0`), sets `_tls_upgrade = true`, and flushes the ClientHello. The `_tls_upgrade` flag distinguishes "initial SSL from constructor" vs "upgraded SSL from start_tls()":

- **`_ssl_poll()`**: When `SSLReady` is reached and `_tls_upgrade` is true, calls `_on_tls_ready()` instead of `_on_connected()`/`_on_started()`.
- **`hard_close()`**: When SSL handshake is incomplete and `_tls_upgrade` is true, calls `_on_tls_failure()` then `_on_closed()` (the application already knew about the plaintext connection). Without `_tls_upgrade`, the initial-SSL path fires `_on_connection_failure()`/`_on_start_failure()` instead.

Preconditions enforced synchronously: connection must be open, not already TLS, not muted, no buffered read data (CVE-2021-23222), no pending writes. Returns `StartTLSError` on failure (connection unchanged). The "no pending writes" check is platform-aware: on POSIX it checks `_has_pending_writes()` (any unconfirmed bytes); on Windows IOCP it checks for un-submitted data only (`_pending_data.size() > _pending_sent`), since submitted-but-unconfirmed writes are already in the kernel's send buffer.

### Send system

`send(data: (ByteSeq | ByteSeqIter))` is fallible — it returns `(SendToken | SendError)` instead of silently dropping data:

- `SendToken` — opaque token identifying the send operation. Delivered to `_on_sent(token)` when data is fully handed to the OS.
- `SendErrorNotConnected` — connection not open (permanent).
- `SendErrorNotWriteable` — socket under backpressure (transient, wait for `_on_unthrottled`).
During SSL handshake (before `_on_connected`/`_on_started`, or before `_on_tls_ready` after `start_tls()`), returns `SendErrorNotConnected`.

`send()` accepts a single buffer (`ByteSeq`) or multiple buffers (`ByteSeqIter`). When multiple buffers are provided, they are sent in a single writev syscall, avoiding per-buffer syscall overhead.

`is_writeable()` lets the application check writeability before calling `send()`.

`_on_sent(token)` always fires in a subsequent behavior turn (via `_notify_sent` on `TCPConnectionActor`), never synchronously during `send()`. If the connection closes with a pending partial write, `_on_send_failed(token)` fires (via `_notify_send_failed`) to notify the application that the accepted send could not be delivered. `_on_send_failed` always arrives after `_on_closed`, which fires synchronously during `hard_close()`.

The library does not queue data on behalf of the application during backpressure. `send()` returns `SendErrorNotWriteable` and the application decides what to do (queue, drop, close, etc.).

#### Write internals

Pending writes use writev on both POSIX and Windows. The internal fields:

- `_pending_data: Array[ByteSeq]` — buffers awaiting delivery. Also keeps `ByteSeq` values alive for the GC while raw pointers reference them in the IOV array built by `PonyTCP.writev`.
- `_pending_writev_total: USize` — total bytes remaining (accounts for `_pending_first_buffer_offset`).
- `_pending_first_buffer_offset: USize` — bytes already sent from `_pending_data(0)`, for partial write resume. COUPLING: points into the buffer owned by `_pending_data(0)` — trimming `_pending_data` without resetting the offset causes a dangling pointer. `_manage_pending_buffer` maintains both.
- `_pending_sent: USize` — Windows only. IOCP entries submitted but not yet completed. Only one WSASend is outstanding at a time; `_iocp_submit_pending()` is a no-op while `_pending_sent > 0`.

The write path uses an enqueue-then-flush pattern:

1. `_enqueue(data)` pushes to `_pending_data` and updates `_pending_writev_total`. Platform-neutral, no I/O.
2. Platform flush: `_send_pending_writes()` (POSIX) or `_iocp_submit_pending()` (Windows). Both call `PonyTCP.writev`, which builds the platform-specific IOV array internally.
3. `_manage_pending_buffer(bytes_sent)` walks `_pending_data`, trims fully-sent entries, and updates `_pending_first_buffer_offset`. Shared across both platforms.

`PonyTCP.writev` takes `Array[ByteSeq] box` and builds `iovec` (POSIX) or `WSABUF` (Windows) arrays internally, hiding the platform-specific tuple layout. Returns bytes sent (POSIX) or buffer count submitted (Windows).

Design: Discussion #150.

### Platform differences

POSIX and Windows (IOCP) have distinct code paths throughout `TCPConnection`, guarded by `ifdef posix`/`ifdef windows`. POSIX uses edge-triggered oneshot events with resubscription; Windows uses IOCP completion callbacks.

## Future Work

- **TCPConnection refactoring**: `tcp_connection.pony` has multiple interleaved state machines encoded as boolean flags (`_connected`, `_closed`, `_shutdown`, `_shutdown_peer`, `_ssl_ready`, `_ssl_failed`, `_throttled`, `_readable`, `_writeable`, `_muted`). Valid state combinations aren't obvious and invalid combinations aren't prevented. `_event_notify` is particularly dense — it handles own-event vs Happy Eyeballs events with nested platform and SSL branching. Design: Discussion #174 — proposes explicit connection lifecycle state objects (inspired by ponylang/postgres) to replace the lifecycle boolean flags. Decisions recorded as comments on the discussion. Readable/writeable/throttled remain as flags (flow control, not lifecycle gates). SSL state deferred to a future iteration.


## Conventions

- Follows the [Pony standard library Style Guide](https://github.com/ponylang/ponyc/blob/main/STYLE_GUIDE.md)
- `_Unreachable()` primitive used for states the compiler can't prove impossible — prints location and exits with code 1
- `TCPConnection.none()` used as a field initializer before real initialization happens via `_finish_initialization` behavior
- Auth hierarchy: `AmbientAuth` > `NetAuth` > `TCPAuth` > `TCPListenAuth` > `TCPServerAuth`, with `TCPConnectAuth` as a separate leaf under `TCPAuth`
- Core lifecycle callbacks are prefixed with `_on_` (private by convention)
- Tests use hardcoded ports per test
- `\nodoc\` annotation on test classes
- Examples have a file-level docstring explaining what they demonstrate
- Self-contained examples use the Listener/Server/Client actor structure (listener accepts connections, launches client on `_on_listening`)
- Each example uses a unique port
