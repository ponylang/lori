# Lori

A Pony TCP networking library. Reimagines the standard library's `net` package with a different design: the connection logic lives in a plain `class` (`TCPConnection`/`TCPListener`) that the user's `actor` delegates to, rather than baking everything into a single actor.

<!-- contributor-only -->
## Contributing with an AI assistant

This is a Pony project. The ponylang org maintains a set of LLM coding skills. Get set up with them before contributing:

- **Not set up yet?** Install them once:

  ```bash
  git clone https://github.com/ponylang/llm-skills.git
  cd llm-skills
  python install.py
  ```

- **Already set up?** Make sure you're on the latest. If you installed with the script above, `git pull` in the directory where you cloned `llm-skills` and the symlinked skills update automatically — if you set them up another way, refresh them however that setup expects.

See the [llm-skills README](https://github.com/ponylang/llm-skills) for details and other harnesses.

When you start working on this project, load the `pony-skills` skill — it tells your assistant which Pony skill to use for each task.

Read [CONTRIBUTING.md](CONTRIBUTING.md).
<!-- /contributor-only -->

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
  _pending_writes.pony      -- _PendingWrites: the write queue (buffers + offset + total)
  timer_token.pony          -- TimerToken class, SetTimerError primitives and type alias
  timer_duration.pony       -- TimerDuration constrained type and validator
  read_buffer.pony          -- Read buffer result types (ReadBufferResized, BufferUntilSet, etc.)
  read_action.pony          -- ReadAction: KeepReading, YieldReading
  _tls_state.pony           -- _TLSState: _NoTLS, _TLS, _TLSDisposed, _TLSFailed; _MakeTLS
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
  socket_result.pony        -- SocketResult primitives + decoder for pony_os_* return values (mirrors ponyc internal type)
  _test.pony                -- Test runner (Main only)
  _test_connection.pony     -- Connection basics, ping-pong, buffer_until, listener tests
  _test_backpressure_drain.pony -- Backpressure drain + unmute read recovery and write-only oneshot read recovery tests
  _test_flow_control.pony   -- Mute/unmute tests (plaintext and SSL)
  _test_send.pony           -- Send, sendv, send-after-close tests
  _test_ssl.pony            -- SSL ping-pong, SSL sendv, SSL handshake state, large-payload framing, and close/hard-close-from-callback tests
  _test_start_tls.pony      -- STARTTLS upgrade, precondition, TLS upgrade state, TLS failure, hard-close-from-callback, and post-upgrade timer tests
  _test_close_while_connecting.pony -- Close/hard_close during connecting phase
  _test_idle_timeout.pony   -- Idle timeout (plaintext + SSL) tests
  _test_yield_read.pony     -- Yield read tests (plaintext and SSL)
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
  send-completion/          -- Per-send completion tracking with SendToken
  socket-options/           -- TCP_NODELAY and OS buffer size tuning
  net-ssl-echo-server/      -- SSL echo server
  net-ssl-infinite-ping-pong/ -- SSL ping-pong
  starttls-ping-pong/       -- STARTTLS upgrade from plaintext to TLS
  connection-timeout/        -- Connection timeout with non-routable address
  timer/                    -- Query-timeout simulation with set_timer()
  yield-read/               -- Cooperative scheduler fairness with YieldReading
stress-tests/
  tcp-swarm/                -- Swarm TCP stress test: churn + per-connection echo oracle
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

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    // handle data
    KeepReading
```

### How to implement a client

```
actor MyClient is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()

  new create(auth: TCPConnectAuth, host: String, port: String) =>
    _tcp_connection = TCPConnection.client(auth, host, port, "", this, this)

  fun ref _connection(): TCPConnection => _tcp_connection

  fun ref _on_connected() => // connected
  fun ref _on_received(data: Array[U8] iso): ReadAction => KeepReading
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

| State | `is_closed()` | `sends_allowed()` | `is_live()` | `idle_timer_fired()` re-arms | Description |
|---|---|---|---|---|---|
| `_ConnectionNone` | false | false | false | no | Before `_finish_initialization`. Most dispatch methods call `_Unreachable()`. Socket options return error values; `idle_timeout` stores the value; `set_timer` returns `SetTimerNotOpen`. `hard_close` is a no-op (dispose can race with initialization). |
| `_ClientConnecting` | false | false | false | no | Happy Eyeballs in progress. `close()` transitions to `_UnconnectedClosing`. |
| `_UnconnectedClosing` | true | false | false | no | Draining inflight Happy Eyeballs after `close()` during connecting. Fires `_on_connection_failure` when all drain. `hard_close()` short-circuits to `_Closed`. |
| `_SSLHandshaking` | false | false | true | no | TCP connected, initial SSL handshake in progress. Application not notified yet. `close()` delegates to `hard_close()`. |
| `_TLSUpgrading` | false | false | true | yes | Established connection upgrading to TLS via `start_tls()`. Application already notified. `close()` delegates to `hard_close()`. |
| `_Open` | false | true | true | yes | Connection established, application notified, I/O active. |
| `_Closing` | true | false | true | no | Graceful shutdown in progress. Flushes writes still queued under backpressure, then sends FIN once the queue drains, and waits for the peer FIN. Still reads to detect FIN. |
| `_Closed` | true | false | false | no | Fully closed. Handles straggler event cleanup only. |

State classes dispatch lifecycle-gated operations (`send`, `close`, `hard_close`, `start_tls`, `read_again`, `receive`, `ssl_handshake_complete`, `own_event`, `foreign_event`, `keepalive`, `getsockopt`, `getsockopt_u32`, `setsockopt`, `setsockopt_u32`, `idle_timeout`, `set_timer`, `idle_timer_fired`) and delegate to TCPConnection methods for the actual work. All I/O, SSL, buffer, and flow control logic remains on TCPConnection.

Each state also answers `is_live()`: whether the connection has a socket fd it can still do I/O on. It is not the same question as "can the application use this" — the fd is live before the app is handed the connection (the SSL handshake) and after the app has gracefully closed it (`_Closing`, draining and reading for the peer's FIN). It is false before the fd exists (connecting) and after a hard close tears it down. `_read()`'s loop checks it at the top of every iteration, before any `_next_message()` or `_fill()`: the application's `_on_received` can `hard_close()` mid-loop, and the loop returns on that transition instead of reading the just-closed fd. It is about the socket, not the SSL session — the session guards itself, see "TLS session state". The two post-establish paths check it before their first read, so a callback that closed the connection skips it. Per-state values are in the table above.

**Private field access**: Pony restricts private field access to the defining type. State classes use helper methods on TCPConnection (`_set_state`, `_decrement_inflight`, `_establish_connection`, `_straggler_cleanup`, etc.) rather than accessing fields directly.

**Flags kept on TCPConnection**: `_shutdown` and `_shutdown_peer` remain as data fields (set by I/O methods, checked by `_Closing`). Flow control flags (`_throttled`, `_readable`, `_writeable`, `_muted`) are orthogonal to lifecycle state, and `_hard_close_cleanup()` clears the first three so a closed connection carries no live flow-control state. Why a hard close is happening is not a flag either: it is a `_HardCloseCause` the caller passes to `_hard_close()` — see "Close causes".

**`_event_notify` dispatch**: A single `if/elseif/else` chain dispatches on event identity: connect timer, idle timer, user timer, socket event (`_event`), or everything else (the `else` branch). Timer identity checks must come before the `event is _event` check. Each timer branch checks `AsioEvent.errored(flags)` first — connect timer errors call `_fire_connect_timer_error()`, idle timer errors call `_cancel_idle_timer()`, and user timer errors call `_cancel_user_timer()`. The `else` branch checks disposable first (destroys stale timer disposables and straggler disposables), then checks for stale errored events from cancelled timers (errored flag set AND event struct is disposable from the prior unsubscribe — destroyed here to prevent misidentification as a Happy Eyeballs straggler), otherwise dispatches to `foreign_event` for Happy Eyeballs stragglers.

Design: Discussion #219.

### Read path

There is one read loop, and every control the application has over reading lives
in it exactly once.

```
fun ref _read() =>
  while _readable do
    if _muted or (not _state.is_live()) then return end
    match _next_message()
    | let m: Array[U8] iso => s._on_received(consume m); <yield check>
    | None => <scheduler yield check>; if _fill(s)? is None then return end
    end
  end
```

- **`_next_message()`** returns the next message for the application, or `None`
  when there aren't enough bytes yet. It returns a value and never calls the
  application, which is what keeps `mute` and `is_live` in the
  loop and out of it. For an SSL connection the message comes from the SSL
  session, which frames it (`ssl.read(_user_buffer_until())`). Otherwise it is
  chopped off `_read_buffer`.
- **`_fill()`** is the only thing that knows whether the connection is using SSL.
  It reads the socket into `_read_buffer`; on an SSL connection it then hands all
  of it to `ssl.receive()` and runs `_ssl_poll()`. It returns the byte count, or
  `None` when the socket has nothing more (read interest is re-armed first), and
  raises when the read fails — a peer close or an unrecoverable error (`_read()`
  hard closes on either).

`_fill()` returns as soon as it has fed the session. `_ssl_poll()` runs handshake
callbacks that can `hard_close()` and dispose the session, so the next look at
the session happens only after the loop has re-checked its guards. Nothing has to
remember to guard it; the loop does.

Reading the SSL session is not read-only: `ssl.read()` in `_next_message()` can make it queue protocol output — a TLS 1.3 KeyUpdate response, a TLS 1.2 renegotiation. `_ssl_poll()` only flushes what `ssl.receive()` produces, so once the session has drained (`_next_message()` returns `None`) `_read()` flushes the read side via `_ssl_flush_sends()` before it blocks on the socket, or a peer waiting on that output would wedge. `_ssl_flush_sends()` does nothing without a live session (so it is a no-op on a plaintext connection, and inert after a hard close) and can `hard_close()` on a write error, so the loop re-checks `is_live()` after it. `mute()` gets the same flush on its way out of the loop: mute is a read-side control and must not hold write-side protocol output, and a mute lasts as long as the application likes.

Undelivered data lives in one place per connection: `_read_buffer` for plaintext,
the SSL session for SSL. `mute()` therefore holds data rather than dropping it on
both, and `unmute()` delivers it before anything read off the socket afterward —
`_next_message()` is asked before `_fill()` is called.

An earlier design had `_ssl_poll()` deliver to the application in a second loop of
its own. Every read-side control then had to be written twice, and two of them
shipped as bugs before the second copy was written: the liveness check now called `is_live()` (a segfault, PR #311) and
`_muted` (issue #313). Do not put a delivery call back into `_ssl_poll()`.

### SSL internals

SSL handshake state is managed by the connection state machine: `_SSLHandshaking` (initial SSL from constructor) and `_TLSUpgrading` (mid-stream upgrade via `start_tls()`). Both transition to `_Open` when `ssl.state()` returns `SSLReady`, dispatched through `_state.ssl_handshake_complete()`. Key behaviors:

- **0-to-N output per input on both sides:** Both read and write can produce zero, one, or many output chunks per input chunk. During handshake, output may be zero (buffered). A single TCP read containing multiple SSL records produces multiple decrypted chunks.
- **`_ssl_poll()`:** Called by `_fill()` after `ssl.receive()` has fed the session new ciphertext. Matches `\exhaustive\` on `ssl.state()`: `SSLReady` dispatches to `_state.ssl_handshake_complete()`, `SSLAuthFail` calls `_hard_close(_TLSAuthFailure)`, `SSLError` calls `hard_close()`, `SSLHandshake` is a no-op (still handshaking), and `SSLDisposed` is `_Unreachable()` (a live `_TLS` session is never disposed; disposing moves `_ssl` to `_TLSDisposed`). The match is exhaustive so a future `SSLState` member fails the build until it is handled here. Then flushes encrypted protocol data (handshake responses, etc.) via `_ssl_flush_sends()`. It does **not** deliver application data — `_read()` takes messages out of the session one at a time via `_next_message()`.
- **Callbacks that close mid-poll:** `_ssl_poll()` runs application code in one place — `ssl_handshake_complete()`, which fires `_on_connected`, `_on_started`, or `_on_tls_ready`. Any of those can call `hard_close()`, which moves the state to `_Closed` and disposes the SSL session while `_ssl_poll()` still holds a `_TLS` alias to it. The trailing `_ssl_flush_sends()` re-matches `_ssl`, finds `_TLSDisposed`, and does nothing; the stale alias is never used again. Graceful `close()` moves to `_Closing`, which still receives and does not dispose, so reading continues there.
- **Client handshake initiation:** When TCP connects, `_ssl_flush_sends()` sends the ClientHello. The state transitions from `_ClientConnecting` to `_SSLHandshaking`. The handshake proceeds via `_fill()` → `ssl.receive()` → `_ssl_poll()`.
- **Ready signaling:** `_SSLHandshaking.ssl_handshake_complete()` transitions to `_Open`, cancels the connect timer, arms the idle timer, and fires `_on_connected`/`_on_started`. `_TLSUpgrading.ssl_handshake_complete()` transitions to `_Open` and fires `_on_tls_ready()`. `_ssl_poll()` dispatches `ssl_handshake_complete()` on every read where the session reports `SSLReady`, which is every read after the handshake. Only `_SSLHandshaking` and `_TLSUpgrading` act on it; `_Open` and `_Closing` return `None`, so the repeat is a no-op. The transition to `_Open` is the one-shot guard — no flag is needed. (`_ClientConnecting`, `_UnconnectedClosing`, `_ConnectionNone`, `_Closed` cannot reach `_ssl_poll` and keep `_Unreachable()`.)
- **Error handling:** Each handshake state has its own hard-close method. `_hard_close_ssl_handshaking()` fires `ConnectionFailedSSL`/`ConnectionFailedTimeout`/`ConnectionFailedTimerError` (client) or `StartFailedSSL` (server). `_hard_close_tls_upgrading()` fires `_on_tls_failure(reason)` then `_on_closed()`. `_hard_close_connected()` (from `_Open`/`_Closing`) fires only `_on_closed()`.
- **Buffer-until handling:** `_next_message()` passes `_user_buffer_until()` to `ssl.read()`, so the SSL session does the framing. `_read_buffer` holds only ciphertext on an SSL connection — `_fill()` feeds all of it to `ssl.receive()` and never chops it — so no framing applies to it.
- **`_enqueue` during handshake:** `_ssl_flush_sends()` pushes handshake protocol data via `_enqueue()`. The `_enqueue()` guard is `not _state.is_closed()`. It does two jobs. It lets handshake output through in `_SSLHandshaking` and `_TLSUpgrading`, where application sends are still refused — so a narrower guard keyed on "can this state send?" would deadlock the handshake. And it stops anything more going on the queue once a close has begun, which matters because `_Closing` keeps reading: `_read()` calls `_ssl_flush_sends()`, and `ssl.read()` can queue protocol output. Do not narrow it in either direction.

Design: Discussion #252.

### TLS session state

`_ssl` is a `_TLSState`, not an `(SSL | None)`. Four variants:

- `_NoTLS` — a plaintext connection, no session, ever.
- `_TLS` — a TLS connection with a live session. The only variant carrying one.
- `_TLSDisposed` — a TLS connection whose session has been disposed.
- `_TLSFailed` — a TLS connection whose session could not be created.

"Is this TLS?" and "may I use the session?" are different questions, and after `ssl.dispose()` they have different answers. `(SSL | None)` could not say "TLS, session gone": clearing the field made `_next_message()` and `_fill()` take their plaintext branches and hand the application ciphertext, and leaving it made `match _ssl` bind a disposed session while looking like a guard. Every site that reached for the session had to ask `_state.is_live()` whether the session it had just matched was really alive. One site did not. That was PR #311's segfault.

`match` is the guard: only `_TLS` carries a session, and it exists only while the session is alive. `_ssl_poll()` can hold a stale `_TLS` alias across a callback that hard-closes, and the trailing `_ssl_flush_sends()` re-matches the field, finds `_TLSDisposed`, and does nothing — it needs no lifecycle check.

`_dispose_tls()` is the only place that disposes. It disposes and moves to `_TLSDisposed` together, so no call site can break the invariant. Disposing without moving leaves a dead session that `_TLS` still binds, and the next use of it is a use-after-free.

`_TLSFailed` exists because the constructors that build a session cannot fail. Previously the failure went into an `_ssl_failed: Bool` and `_ssl` stayed `_NoTLS`, so a connection that asked for TLS and did not get one was indistinguishable from a plaintext connection — only an `if` at the top of `_complete_client_initialization` and `_complete_server_initialization` kept it from carrying application bytes in the clear. `_MakeTLS.client()`/`_MakeTLS.server()` map the failure to `_TLSFailed` in one place, so no constructor can write `_NoTLS` for it. `SSLContext.client()` errors only when OpenSSL allocation fails, so nothing short of fault injection drives this path.

Sites that only ask "is this TLS?" (`_do_start_tls`, `_tcp_buffer_until`, `_establish_connection`, `_complete_server_initialization`) match on `_NoTLS` versus everything else. Sites that need the session and cannot be reached after a close use `_Unreachable()` for `_TLSDisposed`.

### TLS upgrade (STARTTLS)

`start_tls(ssl_ctx, host)` upgrades an established plaintext connection to TLS. It creates an SSL session, transitions to `_TLSUpgrading`, and flushes the ClientHello. No buffer-until migration is needed — once `_ssl` is set, `_next_message()` takes its messages from the session, which frames them. The state distinguishes initial SSL from TLS upgrades:

- **`_TLSUpgrading.ssl_handshake_complete()`**: Transitions to `_Open` and calls `_on_tls_ready()`. No timer arming — the idle timer is already running from the plaintext phase.
- **`_TLSUpgrading.hard_close()`**: Calls `_hard_close_tls_upgrading(cause)`, which fires `_on_tls_failure(reason)` (`TLSAuthFailed` when the cause is `_TLSAuthFailure`, otherwise `TLSGeneralError`) then `_on_closed()` (the application already knew about the plaintext connection).
- **`_TLSUpgrading.send()`**: Returns `SendErrorNotConnected` — sends are blocked during the TLS handshake.
- **`_TLSUpgrading.close()`**: Delegates to `hard_close()` — can't send FIN during TLS handshake.
- **`_TLSUpgrading` is established:** the application has already been notified, so `_TLSUpgrading` delegates socket option, `idle_timeout`, `set_timer`, and `idle_timer_fired` operations to the same helpers as `_Open`.
- **`_TLSUpgrading.sends_allowed()`**: Returns `false` — prevents `is_writeable()` from returning true during handshake.

Preconditions enforced synchronously: connection must be open, not already TLS, not muted, no buffered read data (CVE-2021-23222), no pending writes. Returns `StartTLSError` on failure (connection unchanged). The "no pending writes" check is `_has_pending_writes()` (any unsent bytes) on every platform — writev is synchronous everywhere, so any remaining pending bytes mean the write hasn't fully drained.

Design: Discussion #252.

### Send system

`send(data: (ByteSeq | ByteSeqIter))` is fallible — it returns `(SendToken | SendError)` instead of silently dropping data:

- `SendToken` — opaque token identifying the send operation. Each accepted `send()` gets exactly one terminal callback: `_on_sent(token)` when its bytes are handed to the OS (kernel send buffer, not peer receipt), or `_on_send_failed(token)` if the connection is lost or hard-closed before the bytes are written. A graceful `close()` flushes queued writes first, so sends still pending at a graceful close fire `_on_sent`. Callbacks fire in send order.
- `SendErrorNotConnected` — connection not open (permanent).
- `SendErrorNotWriteable` — socket under backpressure (transient, wait for `_on_unthrottled`).
During SSL handshake (`_SSLHandshaking` or `_TLSUpgrading`), returns `SendErrorNotConnected` directly from the state class without reaching `_do_send()`.

`send()` accepts a single buffer (`ByteSeq`) or multiple buffers (`ByteSeqIter`). When multiple buffers are provided, they are sent in a single writev syscall, avoiding per-buffer syscall overhead.

`is_writeable()` lets the application check writeability before calling `send()`. It and `is_closed()` are the whole public predicate surface, and between them they say what a caller can do about sending: `is_writeable()` means send now (on a plaintext connection it means `send()` returns a token; on an SSL connection the session can still reject the write); neither predicate true means hold the data (still connecting, handshaking, or backpressured); `is_closed()` means drop it, no send will ever be accepted. `(is_writeable, is_closed) == (true, true)` is unreachable. An earlier design had a third predicate, `is_open()`, true in `_Open` and `_TLSUpgrading`. It answered neither question: true in `_TLSUpgrading`, where `send()` fails, and false in `_ClientConnecting` and `_SSLHandshaking`, where a send is refused now but will be accepted if the connection completes. So neither reading told a caller what to do, and internally the one name meant "still connected" at one site and "still fully open" at another. Do not add it back. Issue #308.

A `send()` can close the connection before it returns. The flush inside it applies backpressure on a partial write and runs `_on_throttled` right there, so an application that closes from `_on_throttled` — or a write that fails outright — closes from inside `send()`. The send is still accepted and still gets its callback, but `hard_close()` fires `_on_closed()` synchronously, so the application can see `_on_closed` before `send()` hands back the token.

`_on_sent(token)` always fires in a subsequent behavior turn (via `_notify_sent` on `TCPConnectionActor`), never synchronously during `send()`. On a hard close, every accepted send still pending (not yet `_on_sent`) fires `_on_send_failed(token)` (via `_notify_send_failed`) in send order, so the split between tokens that got `_on_sent` and tokens that got `_on_send_failed` marks exactly how far delivery to the OS reached. `_on_send_failed` always arrives after `_on_closed`, which fires synchronously during `hard_close()`. Because `_on_sent` is delivered by a queued behavior, a token whose bytes reached the OS just as the connection closed can fire `_on_sent` after `_on_closed`.

The library does not queue data on behalf of the application during backpressure. `send()` returns `SendErrorNotWriteable` and the application decides what to do (queue, drop, close, etc.).

#### Write internals

Pending writes use writev on every platform. The internal fields:

- `_pending: _PendingWrites` — the buffers awaiting delivery, the byte offset of the last partial write into the first buffer, and the total bytes remaining. These three must change together — the offset points into the buffer `_buffers(0)` owns, so trimming without resetting it dangles — so `_PendingWrites` owns all three and is the only place they change: `push`, `sent`, and `clear` are its only mutations, and each keeps them consistent. It also keeps the `ByteSeq` values alive for the GC while raw pointers reference them in the IOV array `PonyTCP.writev` builds.
- `_pending_tokens: List[(USize, SendToken)]` — FIFO of (completion offset, token). Each accepted send records the cumulative enqueued-byte offset — into the wire-byte stream `_pending` drains, not an index into its buffers — at which its bytes finish. For SSL the offsets are over ciphertext (enqueued synchronously by `_ssl_enqueue_sends()`), for plaintext over the application bytes.
- `_cumulative_enqueued` / `_cumulative_sent: USize` — running byte totals over `_pending`. `_fire_completed_sends()` fires `_on_sent` for every token whose completion offset `<= _cumulative_sent`, in FIFO order. Both counters reset to 0 when the queue empties, so the offsets stay small.

The write path uses an enqueue-then-flush pattern:

1. `_enqueue(data)` pushes to `_pending` and updates `_cumulative_enqueued`. No I/O.
2. `_send_pending_writes()` flushes via `PonyTCP.writev`, which builds the IOV array internally. It loops while writeable and there is pending data, applying backpressure on a partial write or `SocketResultRetry`, then calls `_fire_completed_sends()` to fire `_on_sent` for the tokens the drain completed.
3. `_manage_pending_buffer(bytes_sent)` tells `_pending` to account for the bytes (it trims fully-sent buffers and advances its offset) and updates `_cumulative_sent`.

`hard_close()` drains `_pending_tokens` to `_on_send_failed` (every remaining token, in FIFO order) via `_hard_close_cleanup`. It fails every token on the queue, without looking at offsets — so the queue has to be truthful before anything that can hard close runs. The write flush calls into the application twice, and both report the sends they have completed first: `_apply_backpressure()` before `_on_throttled` (the application can close from there), and the writev-error branch before `hard_close()`. Without that, a send whose bytes all reached the OS is still on the queue when the callback runs, and a hard close reports it failed — so the split stops marking how far delivery got.

`_do_send` mints the token and pushes it to `_pending_tokens` **before** it flushes. The flush can end the connection — a write error hard closes, and the `_on_throttled` it fires on a partial write lets the application close too — and a token already on the queue gets `_on_sent` when the queue drains past its offset or `_on_send_failed` when a hard close discards the queue. So an accepted send has a terminal callback whatever the flush does. Minting after the flush cannot give that: a send whose bytes the flush had already put on the wire would be reported as `SendErrorNotConnected` and get no callback at all. Do not move the mint back after the flush. Every error return in `_do_send` still sits upstream of the mint, so a send that errored never burns a token id.

`PonyTCP.writev` takes `Array[ByteSeq] box` and builds the `(pointer, size)` IOV array internally; the runtime turns it into `iovec` (POSIX) or `WSABUF` (Windows). Returns `(SocketResult, USize)`: a tri-state result (`SocketResultOk`, `SocketResultRetry`, `SocketResultError`) plus the number of bytes sent. `SocketResultRetry` signals backpressure (`EWOULDBLOCK`/`WSAEWOULDBLOCK`); `SocketResultError` signals an unrecoverable error or peer-close. `PonyTCP.writev_max()` is `IOV_MAX` on POSIX and 1 on Windows, so the flush loop batches accordingly.

Design: Discussion #150.

### Failure reason types

Failure callbacks carry a reason parameter identifying the failure cause. Three type aliases, each following the `start_tls_error.pony` pattern (primitives + type alias):

- **`ConnectionFailureReason`** (`_on_connection_failure`): `ConnectionFailedDNS` (name resolution failed, no TCP attempts), `ConnectionFailedTCP` (resolved but all TCP connections failed), `ConnectionFailedSSL` (TCP connected but SSL handshake failed), `ConnectionFailedTimeout` (connect-to-ready phase timed out), `ConnectionFailedTimerError` (connect timer ASIO subscription failed). The DNS/TCP distinction uses `_had_inflight` (set after `PonyTCP.connect` returns > 0) — real state, which no caller knows. The timeout and timer-error distinctions come from the `_HardCloseCause` the caller passed.
- **`StartFailureReason`** (`_on_start_failure`): `StartFailedSSL` (SSL session creation or handshake failure). Currently a single-variant type — future reasons (e.g. resource limits) can be added without breaking the type alias.
- **`TLSFailureReason`** (`_on_tls_failure`): `TLSAuthFailed` (certificate/auth error), `TLSGeneralError` (protocol error). The distinction comes from the `_HardCloseCause`: `_ssl_poll()` passes `_TLSAuthFailure` when it sees `SSLAuthFail`.

Design: Discussion #201.

### Close causes

`hard_close()` takes no argument: when the application calls it, the call is the reason. Internally it is `_hard_close(cause: _HardCloseCause)`, and the code that knows why passes it.

- `_ConnectTimedOut` — `_fire_connect_timeout()`
- `_ConnectTimerFailed` — `_fire_connect_timer_error()`
- `_TLSAuthFailure` — `_ssl_poll()` on `SSLAuthFail`
- `_UnspecifiedCause` — everything else: the application closed it, or the transport failed. Not `None`: a `_HardCloseCause` is always a real variant, so a hard-close path can match it in full. The reason is still determined, but by the state and `_had_inflight`, not by the cause.

The state decides what the cause becomes. `_hard_close_connecting()` turns it into a `ConnectionFailureReason`, `_hard_close_tls_upgrading()` into a `TLSFailureReason`, `_hard_close_connected()` ignores it and just fires `_on_closed()`.

`_had_inflight` is not a cause. It records whether any TCP attempt ever started, which is what separates `ConnectionFailedDNS` from `ConnectionFailedTCP`. No caller knows it; it accumulates during Happy Eyeballs.

An earlier design had three fields — `_connect_timed_out`, `_connect_timer_errored`, `_ssl_auth_failed` — each set immediately before a `hard_close()` that took no arguments, and dug back out afterwards. They were arguments in the wrong place, and each carried a comment saying so. Do not add a fourth, and do not push the "no distinguishing cause" case back out to a `None` beside the type.

### Idle timeout

Per-connection idle timeout via ASIO timer events. The duration is an `IdleTimeout` constrained type (from `constrained_types` stdlib package) that guarantees a millisecond value in the range 1 to 18,446,744,073,709 (`U64.max_value() / 1_000_000`). The upper bound prevents overflow when converting to nanoseconds internally. `idle_timeout()` accepts `(IdleTimeout | None)` where `None` disables the timer. Fields:

- `_timer_event: AsioEventID` — the ASIO timer event, `AsioEvent.none()` when inactive.
- `_idle_timeout_nsec: U64` — configured timeout duration in nanoseconds, 0 when disabled.

Lifecycle:

- **Arm points**: plaintext branch of `_establish_connection` and `_complete_server_initialization`; `_SSLHandshaking.ssl_handshake_complete()` for initial SSL connections. `_arm_idle_timer()` is a no-op when `_idle_timeout_nsec == 0` or when a timer already exists (idempotency guard). Also called from `_do_idle_timeout()` when setting a timeout on an established connection with no existing timer. `idle_timeout()` dispatches through the state machine — `_Open` and `_TLSUpgrading` delegate to `_do_idle_timeout()` (stores nsec and manages the timer), while all other states delegate to `_store_idle_timeout()` (stores nsec only).
- **Reset points**: `_read()` (once per read event), and `_send_pending_writes()` whenever a `writev` actually writes bytes. The write-side reset lives in `_send_pending_writes()` (not the `send()` path) so it fires for outgoing traffic regardless of source — both an application `send()` and the draining of buffered writes on a writeable event reset the timer. So a slow-but-progressing transfer to a slow peer is not closed as idle while bytes are still moving; only a connection with no bytes in or out for the timeout is closed.
- **Re-arm point**: `_fire_idle_timeout()`, after `_on_idle_timeout` has run. The ASIO timer is one-shot, so a firing only repeats because something arms it again. This one dispatches through the state machine — `_state.idle_timer_fired()` — and only `_Open` and `_TLSUpgrading` re-arm. `_Closing` does not. The callback runs before the dispatch, so a callback that closes the connection gets no re-arm here.

  `_reset_idle_timer()` also re-arms an already-fired timer, and it runs from `_read()` and `_send_pending_writes()` on any I/O, whatever the state (see "Reset points" above). `_Closing` reads and drains. So a closing connection that is still moving bytes goes on firing `_on_idle_timeout`; only a quiet one stops after the firing that `_Closing.idle_timer_fired` does not re-arm.
- **Cancel point**: `_hard_close_connecting()` and `_hard_close_cleanup()` (shared by all connected hard-close paths: `_hard_close_connected`, `_hard_close_ssl_handshaking`, `_hard_close_tls_upgrading`).
- **Event dispatch**: Identity check `event is _timer_event` in `_event_notify`'s `if/elseif/else` chain, before the `event is _event` check. Checks `AsioEvent.errored(flags)` first — if errored, calls `_fire_idle_timer_failure()` which cancels the timer via `_cancel_idle_timer()` (unsubscribing the event and zeroing `_idle_timeout_nsec`) before dispatching `_on_idle_timer_failure`. Cancelling before dispatch lets the callback call `idle_timeout(duration)` to re-arm without hitting the `_arm_idle_timer` idempotency guard. `_timer_event` is cleared synchronously in `_cancel_idle_timer()`, so stale disposable events for cancelled timers fall through to the `else` branch where the disposable check destroys them.

### Connection timeout

Optional one-shot ASIO timer that bounds the connect-to-ready phase for client connections. Covers TCP Happy Eyeballs + SSL handshake. The duration is a `ConnectionTimeout` constrained type (same range as `IdleTimeout`). Fields:

- `_connect_timer_event: AsioEventID` — the ASIO timer event, `AsioEvent.none()` when inactive.
- `_connect_timeout_nsec: U64` — configured timeout in nanoseconds, 0 when disabled.

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

Shrink-back happens in `_resize_read_buffer_if_needed()` when `_bytes_in_read_buffer == 0` and `_read_buffer_size > _read_buffer_min`.

Design: Discussion #212 (implementation plan), Discussion #199 section 11 (design).

### Read yielding

`_on_received` returns a `ReadAction` — `KeepReading` or `YieldReading` — saying what the read loop should do next. `KeepReading` is the trait default. `_read()` matches on the return value:

```pony
match \exhaustive\ s._on_received(consume m)
| KeepReading => None
| YieldReading =>
  _queue_read()
  return
end
```

On resume, `_read()` re-enters (via `_do_read_again()`) and takes the next message before reading from the socket. The state machine guards resume against calling after `hard_close()`: `_Closed.read_again()` is a no-op, while `_Closing.read_again()` still calls `_read()` because the socket's read side is open and needs to detect the peer's FIN.

There is one read loop, so SSL connections yield after the message that returned `YieldReading`, exactly as plaintext ones do.

An earlier design had `yield_read()` set a `_yield_read: Bool` that the loop read afterwards. The callback's answer lived in a field, so where the loop checked that field became load-bearing, and a comment had to defend the spot. A callback that is asked a question should return the answer. Do not put the decision back in a field.

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

POSIX and Windows share a single readiness-based I/O path. Both use one-shot readiness events (epoll/kqueue on POSIX, `ProcessSocketNotifications` on Windows) with resubscription via `PonyAsio.resubscribe_read`/`resubscribe_write`, and call `PonyTCP.receive`/`PonyTCP.writev` synchronously in response. Windows requires ponyc 0.66.0 or later (the release that removed IOCP); the Windows floor is Windows 11 / Windows Server 2022.

Two platform-specific rules remain:

- **writev batch size**: `PonyTCP.writev_max()` is `IOV_MAX` on POSIX, 1 on Windows. The `_send_pending_writes()` loop batches accordingly.
- **Subscribed-fd close**: a subscribed socket fd (one with an ASIO event) is closed via `PonyTCP.close` only on POSIX. On Windows the readiness backend owns the close — it happens when the deferred `ProcessSocketNotifications` REMOVE from `unsubscribe` is processed, so closing earlier strands the disposal handshake and leaks the fd/event. `_close_event_fd()` (used by all subscribed-fd close sites, including the listener) guards this with `ifdef not windows`. Raw, never-subscribed fds (rejected accepts) are closed cross-platform.

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
