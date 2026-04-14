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

**Windows uses `make.ps1`, not the Makefile.** Both run tests with `--sequential`. When making build/test changes, update both files.

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
  timer_token.pony          -- TimerToken class, SetTimerError primitives and type alias
  timer_duration.pony       -- TimerDuration constrained type and validator
  read_buffer.pony          -- Read buffer result types (ReadBufferResized, BufferUntilSet, etc.)
  read_buffer_size.pony     -- ReadBufferSize constrained type, validator, and default
  buffer_size.pony          -- BufferSize constrained type, validator, Streaming primitive
  start_tls_error.pony      -- StartTLSError primitives and type alias
  connection_failure_reason.pony -- ConnectionFailureReason primitives and type alias
  start_failure_reason.pony -- StartFailureReason primitive and type alias
  tls_failure_reason.pony   -- TLSFailureReason primitives and type alias
  idle_timeout.pony         -- IdleTimeout constrained type and validator
  connection_timeout.pony   -- ConnectionTimeout constrained type and validator
  ip_version.pony           -- IP4, IP6, DualStack primitives and IPVersion type alias
  max_spawn.pony            -- MaxSpawn constrained type, validator, and default
  auth.pony                 -- Auth primitives (NetAuth, TCPAuth, TCPListenAuth, etc.)
  pony_tcp.pony             -- FFI wrappers for pony_os_* TCP functions
  pony_asio.pony            -- FFI wrappers for pony_asio_event_* functions
  ossocket.pony             -- _OSSocket: getsockopt/setsockopt wrappers
  ossocketopt.pony          -- OSSockOpt: socket option constants (large, generated)
  _connection_state.pony    -- _ConnectionState trait and lifecycle state classes (including _SSLHandshaking, _TLSUpgrading)
  _panics.pony              -- _Unreachable primitive for impossible states
  _test.pony                -- Test runner (Main only)
  _test_connection.pony     -- Connection basics, ping-pong, buffer_until, listener tests
  _test_backpressure_drain.pony -- Backpressure drain + unmute read recovery test
  _test_flow_control.pony   -- Mute/unmute tests
  _test_send.pony           -- Send, sendv, send-after-close tests
  _test_ssl.pony            -- SSL ping-pong, SSL sendv, and SSL handshake state tests
  _test_start_tls.pony      -- STARTTLS upgrade, precondition, TLS upgrade state, TLS failure, and post-upgrade timer tests
  _test_close_while_connecting.pony -- Close/hard_close during connecting phase
  _test_idle_timeout.pony   -- Idle timeout (plaintext + SSL) tests
  _test_yield_read.pony     -- Yield read tests
  _test_ip_version.pony     -- IPv4/IPv6 specific tests
  _test_constrained_types.pony -- Validation tests for constrained types
  _test_read_buffer.pony    -- Read buffer sizing and buffer_until interaction tests
  _test_socket_options.pony -- Socket option method tests
  _test_connection_timeout.pony -- Connection timeout (plaintext + SSL) tests
  _test_timer.pony          -- General-purpose timer tests
examples/
  backpressure/             -- Backpressure handling with throttle/unthrottle
  echo-server/              -- Simple echo server
  framed-protocol/          -- Length-prefixed framing with buffer_until()
  idle-timeout/             -- Per-connection idle timeout
  infinite-ping-pong/       -- Ping-pong client+server
  ip-version/               -- IPv4-only echo server
  read-buffer-size/         -- Configurable read buffer sizing
  socket-options/           -- TCP_NODELAY and OS buffer size tuning
  net-ssl-echo-server/      -- SSL echo server
  net-ssl-infinite-ping-pong/ -- SSL ping-pong
  starttls-ping-pong/       -- STARTTLS upgrade from plaintext to TLS
  connection-timeout/        -- Connection timeout with non-routable address
  timer/                    -- Query-timeout simulation with set_timer()
  yield-read/               -- Cooperative scheduler fairness with yield_read()
stress-tests/
  open-close/               -- Connection open/close stress test
```

## Architecture

### Core Design Pattern

Lori separates connection logic (class) from actor scheduling (trait):

1. **`TCPConnection`** (class) — All TCP state and I/O logic including SSL. Created with `TCPConnection.client(...)`, `TCPConnection.server(...)`, `TCPConnection.ssl_client(...)`, or `TCPConnection.ssl_server(...)`. All four real constructors accept an optional `read_buffer_size: ReadBufferSize = DefaultReadBufferSize()` parameter that sets both the initial buffer allocation and the shrink-back minimum. Client and SSL client constructors also accept an optional `ip_version: IPVersion = DualStack` parameter to restrict to IPv4 (`IP4`) or IPv6 (`IP6`), and an optional `connection_timeout: (ConnectionTimeout | None) = None` parameter to bound the connect-to-ready phase. Existing plaintext connections can be upgraded to TLS via `start_tls()`. Not an actor itself.
2. **`TCPConnectionActor`** (trait) — The actor trait users implement. Requires `fun ref _connection(): TCPConnection`. Provides behaviors that delegate to the TCPConnection: `_event_notify`, `_read_again`, `dispose`, etc.
3. **Lifecycle event receivers** — `ClientLifecycleEventReceiver` (callbacks: `_on_connected`, `_on_connecting`, `_on_connection_failure(reason)`, `_on_received`, `_on_closed`, `_on_sent`, `_on_send_failed`, `_on_tls_ready`, `_on_tls_failure(reason)`, etc.) and `ServerLifecycleEventReceiver` (callbacks: `_on_started`, `_on_start_failure(reason)`, `_on_received`, `_on_closed`, `_on_sent`, `_on_send_failed`, `_on_tls_ready`, `_on_tls_failure(reason)`, etc.). Both share common callbacks like `_on_received`, `_on_closed`, `_on_throttled`/`_on_unthrottled`, `_on_sent`, `_on_send_failed`, `_on_tls_ready`, `_on_tls_failure`, `_on_idle_timeout`, `_on_idle_timer_failure`, `_on_timer`, `_on_timer_failure`.

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
_ClientConnecting → _SSLHandshaking → _Open (ssl_handshake_complete)
                                    ↘ _Closed (hard_close / SSL error)
_ClientConnecting → _UnconnectedClosing → _Closed (close, drain stragglers)
_ClientConnecting → _Closed (hard_close / all connections failed)
_UnconnectedClosing → _Closed (all inflight drained / hard_close)
_ConnectionNone → _Open (server, plaintext) → _Closing → _Closed
_ConnectionNone → _SSLHandshaking (server, SSL) → _Open (ssl_handshake_complete)
_Open → _TLSUpgrading (start_tls) → _Open (ssl_handshake_complete)
                                   ↘ _Closed (hard_close / TLS error)
```

| State | `is_open()` | `is_closed()` | `sends_allowed()` | Description |
|---|---|---|---|---|
| `_ConnectionNone` | false | false | false | Before `_finish_initialization`. Most dispatch methods call `_Unreachable()`. Socket options return error values; `idle_timeout` stores the value; `set_timer` returns `SetTimerNotOpen`. `hard_close` is a no-op (dispose can race with initialization). |
| `_ClientConnecting` | false | false | false | Happy Eyeballs in progress. `close()` transitions to `_UnconnectedClosing`. |
| `_UnconnectedClosing` | false | true | false | Draining inflight Happy Eyeballs after `close()` during connecting. Fires `_on_connection_failure` when all drain. `hard_close()` short-circuits to `_Closed`. |
| `_SSLHandshaking` | false | false | false | TCP connected, initial SSL handshake in progress. Application not notified yet. `close()` delegates to `hard_close()`. |
| `_TLSUpgrading` | true | false | false | Established connection upgrading to TLS via `start_tls()`. Application already notified. `close()` delegates to `hard_close()`. |
| `_Open` | true | false | true | Connection established, application notified, I/O active. |
| `_Closing` | false | true | false | Graceful shutdown in progress — waiting for peer FIN. Still reads to detect FIN. |
| `_Closed` | false | true | false | Fully closed. Handles straggler event cleanup only. |

State classes dispatch lifecycle-gated operations (`send`, `close`, `hard_close`, `start_tls`, `read_again`, `ssl_handshake_complete`, `own_event`, `foreign_event`, `keepalive`, `getsockopt`, `getsockopt_u32`, `setsockopt`, `setsockopt_u32`, `idle_timeout`, `set_timer`) and delegate to TCPConnection methods for the actual work. All I/O, SSL, buffer, and flow control logic remains on TCPConnection.

**Private field access**: Pony restricts private field access to the defining type. State classes use helper methods on TCPConnection (`_set_state`, `_decrement_inflight`, `_establish_connection`, `_straggler_cleanup`, etc.) rather than accessing fields directly.

**Flags kept on TCPConnection**: `_shutdown` and `_shutdown_peer` remain as data fields (set by I/O methods, checked by `_Closing`). Flow control flags (`_throttled`, `_readable`, `_writeable`, `_muted`, `_yield_read`) are orthogonal to lifecycle state. SSL error flags (`_ssl_failed`, `_ssl_auth_failed`) remain as data fields for callback routing during hard-close. `_ssl_ready` is a one-shot guard in `_ssl_poll()` against persistent `SSLReady` — it prevents the handshake completion logic from re-executing on every read event after the handshake finishes. It is not a lifecycle state (the state machine handles that via `_SSLHandshaking` → `_Open`). Connect timeout flags (`_connect_timed_out`, `_connect_timer_errored`) are set before `hard_close()` to route the failure reason in `_hard_close_connecting()` and `_hard_close_ssl_handshaking()`.

**`_event_notify` dispatch**: A single `if/elseif/else` chain dispatches on event identity: connect timer, idle timer, user timer, socket event (`_event`), or everything else (the `else` branch). Timer identity checks must come before the `event is _event` check. Each timer branch checks `AsioEvent.errored(flags)` first — connect timer errors call `_fire_connect_timer_error()`, idle timer errors call `_cancel_idle_timer()`, and user timer errors call `_cancel_user_timer()`. The `else` branch checks disposable first (destroys stale timer disposables and straggler disposables), then checks for stale errored events from cancelled timers (errored flag set AND event struct is disposable from the prior unsubscribe — destroyed here to prevent misidentification as a Happy Eyeballs straggler), otherwise dispatches to `foreign_event` for Happy Eyeballs stragglers.

Design: Discussion #219.

### SSL internals

SSL handshake state is managed by the connection state machine: `_SSLHandshaking` (initial SSL from constructor) and `_TLSUpgrading` (mid-stream upgrade via `start_tls()`). Both transition to `_Open` when `ssl.state()` returns `SSLReady`, dispatched through `_state.ssl_handshake_complete()`. SSL error flags (`_ssl_failed`, `_ssl_auth_failed`) remain as data fields on `TCPConnection` for callback routing during hard-close. Key behaviors:

- **0-to-N output per input on both sides:** Both read and write can produce zero, one, or many output chunks per input chunk. During handshake, output may be zero (buffered). A single TCP read containing multiple SSL records produces multiple decrypted chunks.
- **`_ssl_poll()` pump:** Called after `ssl.receive()` in `_deliver_received()`. Checks SSL state via `ssl.state()`: `SSLReady` dispatches to `_state.ssl_handshake_complete()` (guarded by `_ssl_ready` to fire only once), `SSLAuthFail` sets `_ssl_auth_failed` then triggers `hard_close()`, `SSLError` triggers `hard_close()` directly. After state checks, delivers decrypted data to the lifecycle event receiver, and flushes encrypted protocol data (handshake responses, etc.) via `_ssl_flush_sends()`.
- **Client handshake initiation:** When TCP connects, `_ssl_flush_sends()` sends the ClientHello. The state transitions from `_ClientConnecting` to `_SSLHandshaking`. The handshake proceeds via `_deliver_received()` → `ssl.receive()` → `_ssl_poll()`.
- **Ready signaling:** `_SSLHandshaking.ssl_handshake_complete()` transitions to `_Open`, cancels the connect timer, arms the idle timer, and fires `_on_connected`/`_on_started`. `_TLSUpgrading.ssl_handshake_complete()` transitions to `_Open` and fires `_on_tls_ready()`. All other states have `_Unreachable()` — the `_ssl_ready` guard in `_ssl_poll()` ensures `ssl_handshake_complete` is only called once.
- **Error handling:** Each handshake state has its own hard-close method. `_hard_close_ssl_handshaking()` fires `ConnectionFailedSSL`/`ConnectionFailedTimeout`/`ConnectionFailedTimerError` (client) or `StartFailedSSL` (server). `_hard_close_tls_upgrading()` fires `_on_tls_failure(reason)` then `_on_closed()`. `_hard_close_connected()` (from `_Open`/`_Closing`) fires only `_on_closed()`.
- **Buffer-until handling:** The `_buffer_until` field always holds the user's requested value. The TCP read layer uses `_tcp_buffer_until()`, which returns `Streaming` when `_ssl` is non-None (SSL record framing doesn't align with application framing). `_ssl_poll()` reads `_buffer_until` directly, converting to `USize` at the `ssl.read()` call site (0 for `Streaming`).
- **`_enqueue` during handshake:** `_ssl_flush_sends()` pushes handshake protocol data via `_enqueue()`. The `_enqueue()` guard uses `not is_closed()` (not `is_open()`) to allow handshake data through `_SSLHandshaking` (where `is_open() = false`).

Design: Discussion #252.

### TLS upgrade (STARTTLS)

`start_tls(ssl_ctx, host)` upgrades an established plaintext connection to TLS. It creates an SSL session, transitions to `_TLSUpgrading`, and flushes the ClientHello. No buffer-until migration is needed — `_tcp_buffer_until()` automatically returns `Streaming` once `_ssl` is set. The state distinguishes initial SSL from TLS upgrades:

- **`_TLSUpgrading.ssl_handshake_complete()`**: Transitions to `_Open` and calls `_on_tls_ready()`. No timer arming — the idle timer is already running from the plaintext phase.
- **`_TLSUpgrading.hard_close()`**: Calls `_hard_close_tls_upgrading()`, which fires `_on_tls_failure(reason)` (where `reason` is `TLSAuthFailed` or `TLSGeneralError` based on `_ssl_auth_failed`) then `_on_closed()` (the application already knew about the plaintext connection).
- **`_TLSUpgrading.send()`**: Returns `SendErrorNotConnected` — sends are blocked during the TLS handshake.
- **`_TLSUpgrading.close()`**: Delegates to `hard_close()` — can't send FIN during TLS handshake.
- **`_TLSUpgrading.is_open()`**: Returns `true` — the application has already been notified. `_TLSUpgrading` delegates socket option, `idle_timeout`, and `set_timer` operations to the same helpers as `_Open`.
- **`_TLSUpgrading.sends_allowed()`**: Returns `false` — prevents `is_writeable()` from returning true during handshake.

Preconditions enforced synchronously: connection must be open, not already TLS, not muted, no buffered read data (CVE-2021-23222), no pending writes. Returns `StartTLSError` on failure (connection unchanged). The "no pending writes" check is platform-aware: on POSIX it checks `_has_pending_writes()` (any unconfirmed bytes); on Windows IOCP it checks for un-submitted data only (`_pending_data.size() > _pending_sent`), since submitted-but-unconfirmed writes are already in the kernel's send buffer.

Design: Discussion #252.

### Send system

`send(data: (ByteSeq | ByteSeqIter))` is fallible — it returns `(SendToken | SendError)` instead of silently dropping data:

- `SendToken` — opaque token identifying the send operation. Delivered to `_on_sent(token)` when data is fully handed to the OS.
- `SendErrorNotConnected` — connection not open (permanent).
- `SendErrorNotWriteable` — socket under backpressure (transient, wait for `_on_unthrottled`).
During SSL handshake (`_SSLHandshaking` or `_TLSUpgrading`), returns `SendErrorNotConnected` directly from the state class without reaching `_do_send()`.

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

- **`ConnectionFailureReason`** (`_on_connection_failure`): `ConnectionFailedDNS` (name resolution failed, no TCP attempts), `ConnectionFailedTCP` (resolved but all TCP connections failed), `ConnectionFailedSSL` (TCP connected but SSL handshake failed), `ConnectionFailedTimeout` (connect-to-ready phase timed out), `ConnectionFailedTimerError` (connect timer ASIO subscription failed). The DNS/TCP distinction uses `_had_inflight` (set after `PonyTCP.connect` returns > 0). The timeout distinction uses `_connect_timed_out` (set by `_fire_connect_timeout()` before calling `hard_close()`). The timer error distinction uses `_connect_timer_errored` (set by `_fire_connect_timer_error()` before calling `hard_close()`).
- **`StartFailureReason`** (`_on_start_failure`): `StartFailedSSL` (SSL session creation or handshake failure). Currently a single-variant type — future reasons (e.g. resource limits) can be added without breaking the type alias.
- **`TLSFailureReason`** (`_on_tls_failure`): `TLSAuthFailed` (certificate/auth error), `TLSGeneralError` (protocol error). The distinction uses `_ssl_auth_failed` (set by `_ssl_poll()` on `SSLAuthFail` before calling `hard_close()`).

Design: Discussion #201.

### Idle timeout

Per-connection idle timeout via ASIO timer events. The duration is an `IdleTimeout` constrained type (from `constrained_types` stdlib package) that guarantees a millisecond value in the range 1 to 18,446,744,073,709 (`U64.max_value() / 1_000_000`). The upper bound prevents overflow when converting to nanoseconds internally. `idle_timeout()` accepts `(IdleTimeout | None)` where `None` disables the timer. Fields:

- `_timer_event: AsioEventID` — the ASIO timer event, `AsioEvent.none()` when inactive.
- `_idle_timeout_nsec: U64` — configured timeout duration in nanoseconds, 0 when disabled.

Lifecycle:

- **Arm points**: plaintext branch of `_establish_connection` and `_complete_server_initialization`; `_SSLHandshaking.ssl_handshake_complete()` for initial SSL connections. `_arm_idle_timer()` is a no-op when `_idle_timeout_nsec == 0` or when a timer already exists (idempotency guard). Also called from `_do_idle_timeout()` when setting a timeout on an established connection with no existing timer. `idle_timeout()` dispatches through the state machine — `_Open` and `_TLSUpgrading` delegate to `_do_idle_timeout()` (stores nsec and manages the timer), while all other states delegate to `_store_idle_timeout()` (stores nsec only).
- **Reset points**: `_read()` (POSIX, once per read event), `_read_completed()` (Windows, once per read event), `send()` success path (after the SSL/plaintext write block).
- **Cancel point**: `_hard_close_connecting()` and `_hard_close_cleanup()` (shared by all connected hard-close paths: `_hard_close_connected`, `_hard_close_ssl_handshaking`, `_hard_close_tls_upgrading`).
- **Event dispatch**: Identity check `event is _timer_event` in `_event_notify`'s `if/elseif/else` chain, before the `event is _event` check. Checks `AsioEvent.errored(flags)` first — if errored, calls `_fire_idle_timer_failure()` which cancels the timer via `_cancel_idle_timer()` (unsubscribing the event and zeroing `_idle_timeout_nsec`) before dispatching `_on_idle_timer_failure`. Cancelling before dispatch lets the callback call `idle_timeout(duration)` to re-arm without hitting the `_arm_idle_timer` idempotency guard. `_timer_event` is cleared synchronously in `_cancel_idle_timer()`, so stale disposable events for cancelled timers fall through to the `else` branch where the disposable check destroys them.

### Connection timeout

Optional one-shot ASIO timer that bounds the connect-to-ready phase for client connections. Covers TCP Happy Eyeballs + SSL handshake. The duration is a `ConnectionTimeout` constrained type (same range as `IdleTimeout`). Fields:

- `_connect_timer_event: AsioEventID` — the ASIO timer event, `AsioEvent.none()` when inactive.
- `_connect_timeout_nsec: U64` — configured timeout in nanoseconds, 0 when disabled.
- `_connect_timed_out: Bool` — set by `_fire_connect_timeout()` before `hard_close()`, read by `_hard_close_connecting()` and `_hard_close_ssl_handshaking()` to route `ConnectionFailedTimeout`.
- `_connect_timer_errored: Bool` — set by `_fire_connect_timer_error()` before `hard_close()`, read by `_hard_close_connecting()` and `_hard_close_ssl_handshaking()` to route `ConnectionFailedTimerError`.

Lifecycle:

- **Arm point**: `_complete_client_initialization`, after `_had_inflight` is set, before `_connecting_callback()`. Only arms when `_had_inflight` is true (at least one TCP attempt started).
- **Cancel points**: `_establish_connection` plaintext branch (before `_on_connected`), `_SSLHandshaking.ssl_handshake_complete()` (before `_on_connected`/`_on_started`), `_hard_close_connecting`, `_hard_close_cleanup` (shared by all connected hard-close paths).
- **Event dispatch**: Identity check `event is _connect_timer_event` in `_event_notify`'s `if/elseif/else` chain, before the idle timer check. Checks `AsioEvent.errored(flags)` first — if errored, calls `_fire_connect_timer_error()` instead of `_fire_connect_timeout()`.

Design: Discussion #234.

### User timer

One-shot general-purpose timer per connection, independent of the idle timeout. No I/O-reset behavior — fires unconditionally after the configured duration. The duration is a `TimerDuration` constrained type (same range as `IdleTimeout`). Fields:

- `_user_timer_event: AsioEventID` — the ASIO timer event, `AsioEvent.none()` when inactive.
- `_next_timer_id: USize` — monotonically increasing counter for minting `TimerToken` values.
- `_user_timer_token: (TimerToken | None)` — the active timer's token, or `None`.

API:
- `set_timer(duration: TimerDuration): (TimerToken | SetTimerError)` — creates a one-shot timer. Dispatches through the state machine: `_Open` and `_TLSUpgrading` delegate to `_do_set_timer()`, all other states return `SetTimerNotOpen`. Returns `SetTimerAlreadyActive` if a timer is already active.
- `cancel_timer(token: TimerToken)` — cancels the timer if the token matches. No-op for stale/wrong tokens. No connection state check (can cancel during `_Closing`).

Error paths:
- **Synchronous**: `set_timer()` returns a `SetTimerError` when preconditions fail — `SetTimerNotOpen` (any non-`_Open`/`_TLSUpgrading` state) or `SetTimerAlreadyActive` (a timer is already armed).
- **Asynchronous**: `_on_timer_failure` fires when `set_timer()` succeeded but the ASIO event subscription later failed (e.g. `ENOMEM` from `kevent`/`epoll_ctl`). The timer is cancelled before dispatch, so the callback can call `set_timer()` to create a new timer without hitting `SetTimerAlreadyActive`.

Internals:
- `_fire_user_timer()` — clears token and event before the callback, then dispatches `_on_timer(token)`. Clearing before dispatch prevents aliasing when the callback calls `set_timer()`.
- `_fire_user_timer_failure()` — cancels the timer via `_cancel_user_timer()` (unsubscribing the event and clearing the token) before dispatching `_on_timer_failure`. Cancel-before-dispatch mirrors `_fire_user_timer` and enables immediate re-arm from the callback.
- `_cancel_user_timer()` — cleanup path for `hard_close`. Unsubscribes and clears without firing the callback.

Event dispatch: identity check `event is _user_timer_event` in `_event_notify`'s `if/elseif/else` chain, after the idle timer check and before the `event is _event` check. Checks `AsioEvent.errored(flags)` first — if errored, calls `_fire_user_timer_failure()` instead of `_fire_user_timer()`.

Cleanup: `_cancel_user_timer()` called from `_hard_close_connecting()` (defensive) and `_hard_close_cleanup()` (shared by all connected hard-close paths). Timers survive `close()` (graceful shutdown) but are cancelled by `hard_close()`.

Stale events after cancel: `_user_timer_event` is cleared to `AsioEvent.none()` synchronously. Stale fire notifications fall through to `foreign_event` (timer flags don't include writeable, so they're silently dropped). Stale disposable notifications fall through to the `else` branch where the disposable check destroys them.

Design: Discussion #233.

### Read buffer sizing

Configurable read buffer with three interacting values:

- **`_read_buffer_min`**: Shrink-back floor. When buffer is empty and oversized, shrinks to this.
- **`_read_buffer_size`**: Current buffer allocation size.
- **buffer_until** (user's requested value): Framing threshold.

Invariant chain: `buffer_until <= _read_buffer_min <= _read_buffer_size`.

API:
- Constructor parameter `read_buffer_size: ReadBufferSize` (default `DefaultReadBufferSize()`, 16384) sets both `_read_buffer_size` and `_read_buffer_min`.
- `set_read_buffer_minimum(new_min: ReadBufferSize)` — sets shrink-back floor, grows buffer if needed.
- `resize_read_buffer(size: ReadBufferSize)` — forces buffer to exact size, lowers minimum if below it.
- `buffer_until(qty: (BufferSize | Streaming))` — returns `BufferSizeAboveMinimum` if `qty` exceeds `_read_buffer_min`. `Streaming` means "deliver all available data."

`_user_buffer_until()` returns the unwrapped buffer-until value as `USize` (0 when `Streaming`) for invariant checks against buffer sizes. `_tcp_buffer_until()` returns the value the TCP read layer should use — `Streaming` when SSL is active, otherwise `_buffer_until`.

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

All socket option methods dispatch through the state machine. `_Open` and `_TLSUpgrading` delegate to `_do_*` helpers (which call `_OSSocket` methods); all other states return error values. Setters return 0 on success or errno on failure. Getters return `(errno, value)`. When the connection is not open, setters return 1 and getters return `(1, 0)`. Use `OSSockOpt` constants for level and option name parameters.

The general-purpose methods (`getsockopt`, `getsockopt_u32`, `setsockopt`, `setsockopt_u32`) and `keepalive` each have their own dispatch method on `_ConnectionState`. The convenience methods (`set_nodelay`, `get_so_rcvbuf`, etc.) are thin wrappers that delegate to the dispatched general methods, mirroring `_OSSocket`'s wrapper structure.

### Platform differences

POSIX and Windows (IOCP) have distinct code paths throughout `TCPConnection`, guarded by `ifdef posix`/`ifdef windows`. POSIX uses edge-triggered oneshot events with resubscription; Windows uses IOCP completion callbacks.

## Conventions

- Follows the [Pony standard library Style Guide](https://github.com/ponylang/ponyc/blob/main/STYLE_GUIDE.md)
- `_Unreachable()` primitive used for states the compiler can't prove impossible — prints location and exits with code 1
- `TCPConnection.none()` used as a field initializer before real initialization happens via `_finish_initialization` behavior
- Auth hierarchy: `AmbientAuth` > `NetAuth` > `TCPAuth` > `TCPListenAuth` > `TCPServerAuth`, with `TCPConnectAuth` as a separate leaf under `TCPAuth`
- Core lifecycle callbacks are prefixed with `_on_` (private by convention)
- Tests use hardcoded ports per test
- Test listeners must store references to ALL actors created in `_on_accept` and `_on_listening`, and dispose every one of them in `_on_closed`. The Pony runtime won't exit while actors with live I/O resources exist, causing CI hangs (especially on macOS).
- `\nodoc\` annotation on test classes
- New tests go in the appropriate `_test_*.pony` file by functional area, not in `_test.pony` (which contains only the `Main` test runner). Register the test class in `Main.tests()` in `_test.pony`.
- Examples have a file-level docstring explaining what they demonstrate
- Self-contained examples use the Listener/Server/Client actor structure (listener accepts connections, launches client on `_on_listening`)
- Each example uses a unique port
