# Lori

A Pony TCP networking library. Reimagines the standard library's `net` package with a different design: the connection logic lives in a plain `class` (`TCPConnection`/`TCPListener`) that the user's `actor` delegates to, rather than baking everything into a single actor.

## Building and Testing

```
make ssl=3.0.x              # build + run unit tests
make test ssl=3.0.x          # same (test is the default)
make test-one t=TestName ssl=3.0.x  # run a single test by name
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
  tcp_listener.pony         -- TCPListener class (accept loop, connection limits, ip_version)
  tcp_listener_actor.pony   -- TCPListenerActor trait (actor wrapper)
  lifecycle_event_receiver.pony -- Client/ServerLifecycleEventReceiver traits
  send_token.pony           -- SendToken class, SendError primitives and type alias
  read_buffer.pony          -- Read buffer result types (ReadBufferResized, ExpectSet, etc.)
  read_buffer_size.pony     -- ReadBufferSize constrained type, validator, and default
  expect.pony               -- Expect constrained type and validator
  start_tls_error.pony      -- StartTLSError primitives and type alias
  connection_failure_reason.pony -- ConnectionFailureReason primitives and type alias
  start_failure_reason.pony -- StartFailureReason primitive and type alias
  tls_failure_reason.pony   -- TLSFailureReason primitives and type alias
  idle_timeout.pony         -- IdleTimeout constrained type and validator
  ip_version.pony           -- IP4, IP6, DualStack primitives and IPVersion type alias
  max_spawn.pony            -- MaxSpawn constrained type, validator, and default
  auth.pony                 -- Auth primitives (NetAuth, TCPAuth, TCPListenAuth, etc.)
  pony_tcp.pony             -- FFI wrappers for pony_os_* TCP functions
  pony_asio.pony            -- FFI wrappers for pony_asio_event_* functions
  ossocket.pony             -- _OSSocket: getsockopt/setsockopt wrappers
  ossocketopt.pony          -- OSSockOpt: socket option constants (large, generated)
  _connection_state.pony    -- _ConnectionState trait and lifecycle state classes
  _panics.pony              -- _Unreachable primitive for impossible states
  _test.pony                -- Tests
examples/
  backpressure/             -- Backpressure handling with throttle/unthrottle
  echo-server/              -- Simple echo server
  framed-protocol/          -- Length-prefixed framing with expect()
  idle-timeout/             -- Per-connection idle timeout
  infinite-ping-pong/       -- Ping-pong client+server
  ip-version/               -- IPv4-only echo server
  read-buffer-size/         -- Configurable read buffer sizing
  socket-options/           -- TCP_NODELAY and OS buffer size tuning
  net-ssl-echo-server/      -- SSL echo server
  net-ssl-infinite-ping-pong/ -- SSL ping-pong
  starttls-ping-pong/       -- STARTTLS upgrade from plaintext to TLS
  yield-read/               -- Cooperative scheduler fairness with yield_read()
stress-tests/
  open-close/               -- Connection open/close stress test
```

## Architecture

### Core Design Pattern

Lori separates connection logic (class) from actor scheduling (trait):

1. **`TCPConnection`** (class) — All TCP state and I/O logic including SSL. Created with `TCPConnection.client(...)`, `TCPConnection.server(...)`, `TCPConnection.ssl_client(...)`, or `TCPConnection.ssl_server(...)`. All four real constructors accept an optional `read_buffer_size: ReadBufferSize = DefaultReadBufferSize()` parameter that sets both the initial buffer allocation and the shrink-back minimum. Client and SSL client constructors also accept an optional `ip_version: IPVersion = DualStack` parameter to restrict to IPv4 (`IP4`) or IPv6 (`IP6`). Existing plaintext connections can be upgraded to TLS via `start_tls()`. Not an actor itself.
2. **`TCPConnectionActor`** (trait) — The actor trait users implement. Requires `fun ref _connection(): TCPConnection`. Provides behaviors that delegate to the TCPConnection: `_event_notify`, `_read_again`, `dispose`, etc.
3. **Lifecycle event receivers** — `ClientLifecycleEventReceiver` (callbacks: `_on_connected`, `_on_connecting`, `_on_connection_failure(reason)`, `_on_received`, `_on_closed`, `_on_sent`, `_on_send_failed`, `_on_tls_ready`, `_on_tls_failure(reason)`, etc.) and `ServerLifecycleEventReceiver` (callbacks: `_on_started`, `_on_start_failure(reason)`, `_on_received`, `_on_closed`, `_on_sent`, `_on_send_failed`, `_on_tls_ready`, `_on_tls_failure(reason)`, etc.). Both share common callbacks like `_on_received`, `_on_closed`, `_on_throttled`/`_on_unthrottled`, `_on_sent`, `_on_send_failed`, `_on_tls_ready`, `_on_tls_failure`, `_on_idle_timeout`.

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

SSL is handled internally by `TCPConnection`. The `ssl_client`/`ssl_server` constructors create an `SSL` session from the provided `SSLContext val`, perform the handshake transparently, and deliver `_on_connected`/`_on_started` only after the handshake completes. If SSL session creation fails, `_on_connection_failure(ConnectionFailedSSL)` (client) or `_on_start_failure(StartFailedSSL)` (server) fires asynchronously. If the handshake fails, `hard_close()` triggers the same failure callbacks.

### Connection lifecycle state machine

TCPConnection uses explicit state objects (`_ConnectionState` trait in `_connection_state.pony`) instead of boolean flags to manage the connection lifecycle. The `_state` field holds the current state, and `_event_notify` dispatches events through it:

```
_ConnectionNone → _ClientConnecting → _Open → _Closing → _Closed
                                    ↘ _Closed (hard_close)
_ConnectionNone → _Open (server) → _Closing → _Closed
```

| State | `is_open()` | `is_closed()` | Description |
|---|---|---|---|
| `_ConnectionNone` | false | false | Before `_finish_initialization`. All methods call `_Unreachable()`. |
| `_ClientConnecting` | false | false | Happy Eyeballs in progress. Has `_pending_close` flag for `close()` during connecting. |
| `_Open` | true | false | Connection established, I/O active. |
| `_Closing` | false | true | Graceful shutdown in progress — waiting for peer FIN. Still reads to detect FIN. |
| `_Closed` | false | true | Fully closed. Handles straggler event cleanup only. |

State classes dispatch lifecycle-gated operations (`send`, `close`, `hard_close`, `start_tls`, `read_again`, `own_event`, `foreign_event`) and delegate to TCPConnection methods for the actual work. All I/O, SSL, buffer, and flow control logic remains on TCPConnection.

**Private field access**: Pony restricts private field access to the defining type. State classes use helper methods on TCPConnection (`_set_state`, `_decrement_inflight`, `_establish_connection`, `_straggler_cleanup`, etc.) rather than accessing fields directly.

**Flags kept on TCPConnection**: `_shutdown` and `_shutdown_peer` remain as data fields (set by I/O methods, checked by `_Closing`). Flow control flags (`_throttled`, `_readable`, `_writeable`, `_muted`, `_yield_read`) are orthogonal to lifecycle state.

**`_event_notify` dispatch**: Timer events and disposable handling stay on TCPConnection. The `is_own_event` check is captured BEFORE dispatch because `_ClientConnecting.foreign_event()` can promote a foreign event to `_event` (Happy Eyeballs winner).

Design: Discussion #219.

### SSL internals

SSL state lives directly in `TCPConnection` (fields `_ssl`, `_ssl_ready`, `_ssl_failed`, `_ssl_expect`, `_ssl_auth_failed`). Key behaviors:

- **0-to-N output per input on both sides:** Both read and write can produce zero, one, or many output chunks per input chunk. During handshake, output may be zero (buffered). A single TCP read containing multiple SSL records produces multiple decrypted chunks.
- **`_ssl_poll()` pump:** Called after `ssl.receive()` in `_deliver_received()`. Checks SSL state, delivers decrypted data to the lifecycle event receiver, and flushes encrypted protocol data (handshake responses, etc.) via `_ssl_flush_sends()`.
- **Client handshake initiation:** When TCP connects, `_ssl_flush_sends()` sends the ClientHello. The handshake proceeds via `_deliver_received()` → `ssl.receive()` → `_ssl_poll()`.
- **Ready signaling:** `_ssl_ready` is set when `ssl.state()` returns `SSLReady`, which triggers `_on_connected`/`_on_started` delivery.
- **Error handling:** `SSLAuthFail` sets `_ssl_auth_failed = true` then triggers `hard_close()`. `SSLError` triggers `hard_close()` directly. `hard_close()` reads `_ssl_auth_failed` to pass `TLSAuthFailed` vs `TLSGeneralError` to `_on_tls_failure` (for TLS upgrades), or `ConnectionFailedSSL`/`StartFailedSSL` to `_on_connection_failure`/`_on_start_failure` (for initial SSL). If the handshake never completed, clients get `_on_connection_failure(ConnectionFailedSSL)` and servers get `_on_start_failure(StartFailedSSL)`.
- **Expect handling:** The application's `expect()` value is stored in `_ssl_expect` as `(Expect | None)` and converted to `USize` at the `ssl.read()` call site (0 for `None`). The TCP read layer uses `None` (read all available) since SSL record framing doesn't align with application framing.

### TLS upgrade (STARTTLS)

`start_tls(ssl_ctx, host)` upgrades an established plaintext connection to TLS. It creates an SSL session, migrates expect state (`_ssl_expect = _expect; _expect = None`), sets `_tls_upgrade = true`, and flushes the ClientHello. The `_tls_upgrade` flag distinguishes "initial SSL from constructor" vs "upgraded SSL from start_tls()":

- **`_ssl_poll()`**: When `SSLReady` is reached and `_tls_upgrade` is true, calls `_on_tls_ready()` instead of `_on_connected()`/`_on_started()`.
- **`hard_close()`**: When SSL handshake is incomplete and `_tls_upgrade` is true, calls `_on_tls_failure(reason)` (where `reason` is `TLSAuthFailed` or `TLSGeneralError` based on `_ssl_auth_failed`) then `_on_closed()` (the application already knew about the plaintext connection). Without `_tls_upgrade`, the initial-SSL path fires `_on_connection_failure(ConnectionFailedSSL)`/`_on_start_failure(StartFailedSSL)` instead.

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

### Failure reason types

Failure callbacks carry a reason parameter identifying the failure cause. Three type aliases, each following the `start_tls_error.pony` pattern (primitives + type alias):

- **`ConnectionFailureReason`** (`_on_connection_failure`): `ConnectionFailedDNS` (name resolution failed, no TCP attempts), `ConnectionFailedTCP` (resolved but all TCP connections failed), `ConnectionFailedSSL` (TCP connected but SSL handshake failed). The DNS/TCP distinction uses `_had_inflight` (set after `PonyTCP.connect` returns > 0).
- **`StartFailureReason`** (`_on_start_failure`): `StartFailedSSL` (SSL session creation or handshake failure). Currently a single-variant type — future reasons (e.g. resource limits) can be added without breaking the type alias.
- **`TLSFailureReason`** (`_on_tls_failure`): `TLSAuthFailed` (certificate/auth error), `TLSGeneralError` (protocol error). The distinction uses `_ssl_auth_failed` (set by `_ssl_poll()` on `SSLAuthFail` before calling `hard_close()`).

Design: Discussion #201.

### Idle timeout

Per-connection idle timeout via ASIO timer events. The duration is an `IdleTimeout` constrained type (from `constrained_types` stdlib package) that guarantees a millisecond value in the range 1 to 18,446,744,073,709 (`U64.max_value() / 1_000_000`). The upper bound prevents overflow when converting to nanoseconds internally. `idle_timeout()` accepts `(IdleTimeout | None)` where `None` disables the timer. Fields:

- `_timer_event: AsioEventID` — the ASIO timer event, `AsioEvent.none()` when inactive.
- `_idle_timeout_nsec: U64` — configured timeout duration in nanoseconds, 0 when disabled.

Lifecycle:

- **Arm points**: `_complete_server_initialization` (after `_set_writeable()`) and `_event_notify` Happy Eyeballs success (after `_set_readable()`). `_arm_idle_timer()` is a no-op when `_idle_timeout_nsec == 0`. Also called from `idle_timeout()` when setting a timeout on an established connection with no existing timer.
- **Reset points**: `_read()` (POSIX, once per read event), `_read_completed()` (Windows, once per read event), `send()` success path (after the SSL/plaintext write block).
- **Cancel point**: `hard_close()` in both the not-connected branch (before `return`) and the connected branch (before `PonyAsio.unsubscribe(_event)`).
- **Event dispatch**: Identity check `event is _timer_event` at the top of `_event_notify`, before the main `event is _event` check. Returns immediately after firing. `_timer_event` is cleared synchronously in `_cancel_idle_timer()`, so stale disposable events for cancelled timers route through the existing catch-all at the end of `_event_notify` (which calls `PonyAsio.destroy`).

### Read buffer sizing

Configurable read buffer with three interacting values:

- **`_read_buffer_min`**: Shrink-back floor. When buffer is empty and oversized, shrinks to this.
- **`_read_buffer_size`**: Current buffer allocation size.
- **expect** (user's requested value): Framing threshold.

Invariant chain: `expect <= _read_buffer_min <= _read_buffer_size`.

API:
- Constructor parameter `read_buffer_size: ReadBufferSize` (default `DefaultReadBufferSize()`, 16384) sets both `_read_buffer_size` and `_read_buffer_min`.
- `set_read_buffer_minimum(new_min: ReadBufferSize)` — sets shrink-back floor, grows buffer if needed.
- `resize_read_buffer(size: ReadBufferSize)` — forces buffer to exact size, lowers minimum if below it.
- `expect(qty: (Expect | None))` — returns `ExpectAboveBufferMinimum` if `qty` exceeds `_read_buffer_min`. `None` means "deliver all available data."

`_user_expect()` returns the unwrapped expect value as `USize` (0 when both `_expect` and `_ssl_expect` are `None`) for invariant checks against buffer sizes.

Shrink-back happens in `_resize_read_buffer_if_needed()` when `_bytes_in_read_buffer == 0` and `_read_buffer_size > _read_buffer_min`. On Windows, a post-loop call to `_resize_read_buffer_if_needed()` was added in `_read_completed()` and `_windows_resume_read()` because the existing calls inside the `while _there_is_buffered_read_data()` loop can never see `_bytes_in_read_buffer == 0`.

Design: Discussion #212 (implementation plan), Discussion #199 section 11 (design).

### Read yielding

`yield_read()` lets the application exit the read loop cooperatively, giving other actors a chance to run. Reading resumes automatically in the next scheduler turn via `_read_again()`. Field:

- `_yield_read: Bool` — set by `yield_read()`, cleared by the yield check in the dispatch loop.

The yield check is placed immediately after `_deliver_received()` in three locations:

- **POSIX `_read()`**: Inside the inner `while not _muted and _there_is_buffered_read_data()` loop. When triggered, calls `e._read_again()` and returns, exiting both inner and outer loops. On resume, `_read()` re-enters and processes remaining buffered data before reading from the socket.
- **Windows `_read_completed()`**: Same position. The return skips the `_queue_read()` at the end — resumption happens via `_read_again()` instead.
- **Windows `_windows_resume_read()`**: Mirrors the `_read_completed()` dispatch loop. Needed because on Windows, yielding with unprocessed buffered data and just calling `_queue_read()` (which submits an IOCP read) would leave the buffered data unprocessed until new data arrives from the peer. `_windows_resume_read()` processes buffered data first, then submits the IOCP read. The state machine guards against calling this after `hard_close()`: `_Closed.read_again()` is a no-op, while `_Closing.read_again()` correctly calls `_windows_resume_read()` because the socket is still connected and needs an IOCP read to detect the peer's FIN.

**SSL granularity**: `yield_read()` operates at TCP-read granularity. All SSL-decrypted messages from a single `ssl.receive()` call are delivered inside `_ssl_poll()` before the yield check fires. Per-SSL-message yielding would require changes to `_ssl_poll()` and handling partially-consumed SSL buffers on resume.

### Socket options

`TCPConnection` exposes commonly-tuned socket options as dedicated convenience methods, grouped with `keepalive()`:

- `set_nodelay(state: Bool): U32` — enable/disable TCP_NODELAY (Nagle's algorithm). Uses `OSSockOpt.ipproto_tcp()` as the socket level.
- `set_so_rcvbuf(bufsize: U32): U32` / `get_so_rcvbuf(): (U32, U32)` — OS receive buffer size.
- `set_so_sndbuf(bufsize: U32): U32` / `get_so_sndbuf(): (U32, U32)` — OS send buffer size.

For options without dedicated methods, four general-purpose methods expose the full `getsockopt(2)`/`setsockopt(2)` interface:

- `getsockopt(level, option_name, option_max_size): (U32, Array[U8] iso^)` — raw bytes get.
- `getsockopt_u32(level, option_name): (U32, U32)` — U32 convenience get.
- `setsockopt(level, option_name, option): U32` — raw bytes set.
- `setsockopt_u32(level, option_name, option): U32` — U32 convenience set.

All methods guard with `is_open()`. Setters return 0 on success or errno on failure. Getters return `(errno, value)`. When the connection is not open, setters return 1 and getters return `(1, 0)`. All delegate to `_OSSocket` methods in `ossocket.pony`. Use `OSSockOpt` constants for level and option name parameters.

Note: `keepalive()` predates these methods and uses `_state.is_open()` (updated from the original `_connected` check when the lifecycle state machine was introduced).

### Platform differences

POSIX and Windows (IOCP) have distinct code paths throughout `TCPConnection`, guarded by `ifdef posix`/`ifdef windows`. POSIX uses edge-triggered oneshot events with resubscription; Windows uses IOCP completion callbacks.

## Future Work

- **SSL state machine**: The lifecycle boolean flags (`_connected`, `_closed`) have been replaced by explicit state objects (Discussion #219), but SSL state (`_ssl_ready`, `_ssl_failed`, `_ssl_auth_failed`, `_tls_upgrade`) still uses boolean flags. A future iteration could introduce SSL-specific state objects. Design origin: Discussion #174.


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
