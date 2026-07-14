"""
# Lori Package

Lori is a TCP networking library that separates connection logic from actor
scheduling. Unlike the standard library's `net` package, which bakes connection
handling into a single actor, lori puts the TCP state machine in a plain
[`TCPConnection`](/lori/lori-TCPConnection/) class that your actor delegates to.
This separation gives you control over how your actor is structured while lori
handles the low-level I/O.

To build a TCP application with lori, you implement an actor that mixes in two
traits: [`TCPConnectionActor`](/lori/lori-TCPConnectionActor/) (which wires up
the ASIO event plumbing) and a lifecycle event receiver
([`ServerLifecycleEventReceiver`](/lori/lori-ServerLifecycleEventReceiver/) or
[`ClientLifecycleEventReceiver`](/lori/lori-ClientLifecycleEventReceiver/)) that
delivers callbacks like `_on_received`, `_on_connected`, and `_on_closed`.

## Echo Server

Here is a complete echo server. It has two actors: a listener that accepts
connections and a connection handler that echoes data back to the client.

```pony
use "lori"

actor Main
  new create(env: Env) =>
    EchoServer(TCPListenAuth(env.root), "", "7669", env.out)

actor EchoServer is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _out: OutStream
  let _server_auth: TCPServerAuth

  new create(listen_auth: TCPListenAuth,
    host: String,
    port: String,
    out: OutStream)
  =>
    _out = out
    _server_auth = TCPServerAuth(listen_auth)
    _tcp_listener = TCPListener(listen_auth, host, port, this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): Echoer =>
    Echoer(_server_auth, fd, _out)

  fun ref _on_listening() =>
    _out.print("Echo server started.")

  fun ref _on_listen_failure() =>
    _out.print("Couldn't start Echo server.")

actor Echoer is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _out: OutStream

  new create(auth: TCPServerAuth, fd: U32, out: OutStream) =>
    _out = out
    _tcp_connection = TCPConnection.server(auth, fd, this, this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    _tcp_connection.send(consume data)
    KeepReading

  fun ref _on_closed() =>
    _out.print("Connection closed.")
```

The listener actor implements
[`TCPListenerActor`](/lori/lori-TCPListenerActor/). It owns a
[`TCPListener`](/lori/lori-TCPListener/) and must provide `_listener()` to
return it. When a client connects, `_on_accept` is called with the raw file
descriptor. You create and return a connection-handling actor from there.

The connection handler implements both `TCPConnectionActor` and
`ServerLifecycleEventReceiver`. It owns a `TCPConnection` and must provide
`_connection()` to return it. Data arrives via `_on_received`.

Note the `TCPConnection.none()` and `TCPListener.none()` field initializers.
Pony requires fields to be initialized before the constructor body runs, but the
real connection setup happens asynchronously. The `none()` constructors provide
safe placeholder values that are replaced by real initialization via the
`_finish_initialization` behavior.

## Client

Here is a client that connects to a server and sends a message:

```pony
use "lori"

actor MyClient is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()

  new create(auth: TCPConnectAuth, host: String, port: String) =>
    _tcp_connection = TCPConnection.client(auth, host, port, "", this, this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _tcp_connection.send("Hello, server!")

  fun ref _on_connection_failure(reason: ConnectionFailureReason) =>
    // DNS, TCP, SSL, timeout, or timer error failure
    None

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    // Handle response from server
    KeepReading
```

Clients use `ClientLifecycleEventReceiver` instead of
`ServerLifecycleEventReceiver`. The key difference is the connection lifecycle:
clients get `_on_connecting` (called as connection attempts are in progress),
`_on_connected` (ready for data), and `_on_connection_failure` (all attempts
failed, with a [`ConnectionFailureReason`](/lori/lori-ConnectionFailureReason/)
indicating the failure stage). Servers get `_on_started` (ready for data) and
`_on_start_failure`.

## Sending Data

Unlike many networking libraries, `send()` is fallible. It returns
`(SendToken | SendError)` rather than silently dropping data:

```pony
match _tcp_connection.send("some data")
| let token: SendToken =>
  // Accepted. The token comes back in _on_sent, or _on_send_failed on a drop.
  None
| SendErrorNotConnected =>
  // Connection is not open.
  None
| SendErrorNotWriteable =>
  // Under backpressure. Wait for _on_unthrottled before retrying.
  None
end
```

[`SendToken`](/lori/lori-SendToken/) is an opaque value identifying the send
operation. Each accepted `send()` gets exactly one terminal callback: the
token comes back to `_on_sent` once its bytes reach the OS, or to
`_on_send_failed` if the connection closes first. Callbacks arrive in send
order, always in a later behavior turn, never during `send()`. "Handed to the
OS" means written to the kernel send buffer, not received by the peer.

The library does not queue data during backpressure. When `send()` returns
[`SendErrorNotWriteable`](/lori/lori-SendErrorNotWriteable/), the application
decides what to do: queue, drop, or close. Use `_on_throttled` and
`_on_unthrottled` to track backpressure state, or check `is_writeable()` before
calling `send()`.

`send()` accepts both a single buffer (`ByteSeq`) and multiple buffers
(`ByteSeqIter`). When a protocol sends structured data (e.g. a length header
followed by a payload), passing multiple buffers sends them in a single
syscall — avoiding both the per-buffer syscall overhead of calling `send()`
multiple times and the cost of copying into a contiguous buffer:

```pony
// Single buffer
_tcp_connection.send("Hello, world!")

// Multiple buffers — one syscall
let header: Array[U8] val = _encode_header(payload.size())
_tcp_connection.send(recover val [as ByteSeq: header; payload] end)
```

## SSL

Adding SSL to a connection requires only a constructor change. Use
`TCPConnection.ssl_client` or `TCPConnection.ssl_server` with an
`SSLContext val`:

```pony
use "lori"
use "ssl/net"

actor SSLEchoer is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()

  new create(auth: TCPServerAuth, sslctx: SSLContext val, fd: U32) =>
    _tcp_connection = TCPConnection.ssl_server(auth, sslctx, fd, this, this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    _tcp_connection.send(consume data)
    KeepReading

  fun ref _on_start_failure(reason: StartFailureReason) =>
    // SSL handshake failed
    None
```

SSL is handled entirely inside `TCPConnection`. The handshake runs
transparently after the TCP connection is established, and `_on_connected`
(client) or `_on_started` (server) fires only after the handshake completes. If
the handshake fails, clients get `_on_connection_failure` (with
[`ConnectionFailedSSL`](/lori/lori-ConnectionFailedSSL/)) and servers get
`_on_start_failure` (with [`StartFailedSSL`](/lori/lori-StartFailedSSL/)).
The rest of the application code (sending, receiving, closing) is identical
to the non-SSL case.

## TLS Upgrade (STARTTLS)

Some protocols (PostgreSQL, SMTP, LDAP) require upgrading an existing plaintext
connection to TLS mid-stream. Use `start_tls()` on an established connection to
initiate a TLS handshake:

```pony
use "lori"
use "ssl/net"

actor MyStartTLSClient is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _sslctx: SSLContext val

  new create(auth: TCPConnectAuth, sslctx: SSLContext val,
    host: String, port: String)
  =>
    _sslctx = sslctx
    _tcp_connection = TCPConnection.client(auth, host, port, "", this, this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    // Send protocol-specific upgrade request over plaintext
    _tcp_connection.send("STARTTLS")

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    let msg = String.from_array(consume data)
    if msg == "OK" then
      // Server agreed to upgrade — initiate TLS handshake
      match _tcp_connection.start_tls(_sslctx, "localhost")
      | let err: StartTLSError => None // handle error
      end
    end
    KeepReading

  fun ref _on_tls_ready() =>
    // TLS handshake complete — now sending encrypted data
    _tcp_connection.send("encrypted payload")

  fun ref _on_tls_failure(reason: TLSFailureReason) =>
    // TLS handshake failed — _on_closed will follow
    None
```

`start_tls()` returns `None` when the handshake has been started, or a
[`StartTLSError`](/lori/lori-StartTLSError/) if the upgrade cannot proceed. The
connection must be open, not already TLS, not muted, and have no buffered read
data or pending writes. During the handshake, `send()` returns
`SendErrorNotConnected`. When the handshake completes, `_on_tls_ready()` fires.
If it fails, `_on_tls_failure` fires (with a
[`TLSFailureReason`](/lori/lori-TLSFailureReason/) distinguishing
authentication errors from protocol errors) followed by `_on_closed()`.

## Idle Timeout

`idle_timeout()` sets a per-connection timer that fires when no data is sent
or received for the configured duration. Idle timeout is disabled by default.
The duration is an [`IdleTimeout`](/lori/lori-IdleTimeout/) value — a
constrained type that guarantees a millisecond value in the range 1 to
18,446,744,073,709. Pass `None` to disable:

```pony
fun ref _on_started() =>
  // Close connections idle for more than 30 seconds
  match MakeIdleTimeout(30_000)
  | let t: IdleTimeout =>
    _tcp_connection.idle_timeout(t)
  end

fun ref _on_idle_timeout() =>
  _tcp_connection.close()
```

The timer resets on every successful `send()` and every received data event.
It automatically re-arms after each firing — the application decides what to
do (close, send a keepalive, log, etc.). Call `idle_timeout(None)` to disable.

If the idle timer's ASIO event subscription fails (e.g. under kernel memory
pressure), the timer is cancelled and `_on_idle_timer_failure()` fires instead
of `_on_idle_timeout()`. Override it to log, close, or retry
`idle_timeout(duration)` — the default is a silent no-op.

Idle timeout uses a per-connection ASIO timer event, requiring no extra actors
or shared state. This avoids the muting-livelock problem that occurs with
shared `Timers` actors under backpressure.

This is independent of TCP keepalive (`keepalive()`). TCP keepalive is a
transport-level dead-peer probe. Idle timeout is application-level inactivity
detection.

## Connection Timeout

Client connections can hang indefinitely when SYN packets are black-holed or
an SSL handshake stalls. The `connection_timeout` constructor parameter bounds
the connect-to-ready phase — TCP Happy Eyeballs and (for SSL connections) the
TLS handshake. If the timeout fires before `_on_connected`, the connection
fails with [`ConnectionFailedTimeout`](/lori/lori-ConnectionFailedTimeout/).

```pony
match MakeConnectionTimeout(5_000)
| let ct: ConnectionTimeout =>
  _tcp_connection = TCPConnection.client(auth, host, port, "", this, this
    where connection_timeout = ct)
end
```

Connection timeout is disabled by default (`None`). The duration is a
[`ConnectionTimeout`](/lori/lori-ConnectionTimeout/) value — a constrained type
with the same range as `IdleTimeout` (1 to 18,446,744,073,709 milliseconds).
The timer is a one-shot: it either fires and fails the connection, or is
cancelled when the connection becomes ready.

The timer is armed after `PonyTCP.connect` returns, so it does not cover DNS
resolution time. If DNS itself blocks (common with unresponsive nameservers),
the total wait will exceed the configured timeout by the DNS resolution time.

```pony
fun ref _on_connection_failure(reason: ConnectionFailureReason) =>
  match reason
  | ConnectionFailedTimeout => // timed out
  | ConnectionFailedDNS => // name resolution failed
  | ConnectionFailedTCP => // all TCP attempts failed
  | ConnectionFailedSSL => // SSL handshake failed
  | ConnectionFailedTimerError => // connect timer subscription failed
  end
```

## General-Purpose Timer

`set_timer()` creates a one-shot timer that fires `_on_timer()` after a
configured duration. Unlike `idle_timeout()`, this timer has no I/O-reset
behavior — it fires unconditionally regardless of send/receive activity. There
is no automatic re-arming; call `set_timer()` again from `_on_timer()` for
repetition.

```pony
fun ref _on_started() =>
  match MakeTimerDuration(10_000)
  | let d: TimerDuration =>
    match _tcp_connection.set_timer(d)
    | let t: TimerToken =>
      _query_timer = t
    | let err: SetTimerError => None // handle error
    end
  end

fun ref _on_timer(token: TimerToken) =>
  // Timer fired — take action (close, retry, etc.)
  _tcp_connection.close()
```

The duration is a [`TimerDuration`](/lori/lori-TimerDuration/) value — a
constrained type with the same range as `IdleTimeout` (1 to
18,446,744,073,709 milliseconds). Only one timer can be active at a time;
calling `set_timer()` while one is active returns
[`SetTimerAlreadyActive`](/lori/lori-SetTimerAlreadyActive/). Cancel with
`cancel_timer(token)` before setting a new one. The timer is cancelled by
`hard_close()` but survives `close()`.

Timers have two error paths. `set_timer()` returns a
[`SetTimerError`](/lori/lori-SetTimerError/) synchronously when preconditions
prevent the timer from being created. If `set_timer()` succeeded but the
ASIO event subscription later fails (e.g. under kernel memory pressure),
the timer is cancelled and `_on_timer_failure()` fires instead of
`_on_timer()`. The token the application was waiting on is no longer
valid; override the callback to retry or close as appropriate.

## Flow Control

When an application can't keep up with what a connection is delivering, it
calls `mute()` to stop reading and `unmute()` to start again. Both halves
matter: a connection that mutes and never unmutes never reads again.

```pony
fun ref _on_received(data: Array[U8] iso): ReadAction =>
  _work_queue.push(consume data)
  if (not _muted) and (_work_queue.size() >= _high_water) then
    _tcp_connection.mute()
    _muted = true
  end
  KeepReading

// Called as items are processed off _work_queue.
be work_completed() =>
  if _muted and (_work_queue.size() <= _low_water) then
    _tcp_connection.unmute()
    _muted = false
  end
```

`mute()` takes effect immediately. Called from `_on_received`, nothing further
is delivered. Whatever the connection has read but not yet delivered is held,
and `unmute()` delivers it before anything read off the socket afterward. This
holds for plaintext and SSL connections alike.

Held data only survives to an `unmute()`. Closing a muted connection drops it:
`close()` on a muted connection hard closes, and `dispose()` always does. There
is no way to deliver held data without also resuming reads — an application that
needs it has to `unmute()` and keep processing until it has caught up, taking
whatever else arrives in the meantime.

While muted, the connection reads nothing off the socket, so a peer's close is
not detected until `unmute()` resumes reading. A muted connection also holds a
live I/O resource, and the Pony runtime does not exit while any actor holds one,
so a program that mutes a connection and leaves it muted never exits. The
application must end that state: `unmute()` the connection or `close()` it.

## Read Yielding

Under sustained inbound traffic, a single connection's read loop can monopolize
the Pony scheduler. `_on_received` returns a
[`ReadAction`](/lori/lori-ReadAction/) saying what the read loop should do next.
Return [`YieldReading`](/lori/lori-YieldReading/) to stop after this message and
give other actors a turn; reading resumes on its own in the next scheduler turn.

```pony
fun ref _on_received(data: Array[U8] iso): ReadAction =>
  _received_count = _received_count + 1

  // Yield every 10 messages to let other actors run
  if (_received_count % 10) == 0 then
    return YieldReading
  end

  KeepReading
```

[`KeepReading`](/lori/lori-KeepReading/) is the default, so a receiver that
never overrides `_on_received` keeps reading. Any yield policy works — message
count, byte threshold, time-based — because the decision is made per message.

Unlike `mute()`/`unmute()`, which persistently stop reading until reversed,
`YieldReading` is a one-shot pause. The yield takes effect after the message
that returned it. That is true of SSL connections too: a message decrypted
from the same TCP read as the one you yielded on waits for the next scheduler
turn like any other.

## Read Buffer Size

The read buffer defaults to 16KB. To start with a different size, pass a
[`ReadBufferSize`](/lori/lori-ReadBufferSize/) to the constructor:

```pony
match MakeReadBufferSize(512)
| let rbs: ReadBufferSize =>
  _tcp_connection = TCPConnection.server(auth, fd, this, this
    where read_buffer_size = rbs)
end
```

At runtime, use `set_read_buffer_minimum()` to change the shrink-back floor and
`resize_read_buffer()` to force the buffer to a specific size:

```pony
match MakeReadBufferSize(8192)
| let rbs: ReadBufferSize =>
  // Raise the minimum for bulk transfer
  _tcp_connection.set_read_buffer_minimum(rbs)
  // Resize the buffer to match
  _tcp_connection.resize_read_buffer(rbs)
end
```

The `buffer_until()` method accepts `(BufferSize | Streaming)` where `Streaming`
means "deliver all available data." The invariant chain is: `buffer_until <=
read_buffer_min <= read_buffer_size`. Setting buffer_until above the buffer
minimum returns
[`BufferSizeAboveMinimum`](/lori/lori-BufferSizeAboveMinimum/) — raise the
minimum first, then set buffer_until. Resizing below the current buffer_until
returns
[`ReadBufferResizeBelowBufferSize`](/lori/lori-ReadBufferResizeBelowBufferSize/)
and resizing below the amount of unprocessed data in the buffer returns
[`ReadBufferResizeBelowUsed`](/lori/lori-ReadBufferResizeBelowUsed/).

When the buffer is empty and larger than the minimum, it automatically shrinks
back to the minimum size.

## Socket Options

`TCPConnection` exposes commonly-tuned socket options for connected sockets.
All methods dispatch through the connection state machine and return an error
indicator when the connection is not open.

**TCP_NODELAY** disables Nagle's algorithm so small writes are sent immediately:

```pony
fun ref _on_started() =>
  // Disable Nagle for low-latency responses
  _tcp_connection.set_nodelay(true)
```

**OS buffer sizes** control the kernel's receive and send buffers. The OS may
round the requested size up to a platform-specific minimum:

```pony
fun ref _on_started() =>
  _tcp_connection.set_so_rcvbuf(65536)
  _tcp_connection.set_so_sndbuf(65536)

  // Read back the actual values
  (let errno: U32, let actual: U32) = _tcp_connection.get_so_rcvbuf()
  if errno == 0 then
    // actual may be >= 65536 due to OS rounding
  end
```

All setters return `U32` — 0 on success, or a non-zero errno on failure.
Getters return `(U32, U32)` — (errno, value).

**General-purpose access** is available via `getsockopt`/`setsockopt` and their
`_u32` variants for any option in [`OSSockOpt`](/lori/lori-OSSockOpt/). For
commonly-tuned options, prefer the dedicated methods above.

```pony
fun ref _on_started() =>
  // Set TCP_KEEPIDLE via the general-purpose interface
  _tcp_connection.setsockopt_u32(
    OSSockOpt.ipproto_tcp(), OSSockOpt.tcp_keepidle(), 60)
```

## Connection Limits

`TCPListener` accepts an optional `limit` parameter to cap the number of
concurrent connections. The default limit is 100,000 connections
([`DefaultMaxSpawn`](/lori/lori-DefaultMaxSpawn/)). Pass `None` to disable the
limit entirely:

```pony
// Use a custom limit
match MakeMaxSpawn(100)
| let limit: MaxSpawn =>
  _tcp_listener = TCPListener(listen_auth, host, port, this where limit = limit)
end

// No connection limit
_tcp_listener = TCPListener(listen_auth, host, port, this where limit = None)
```

When the limit is reached, the listener pauses accepting. As connections close,
it resumes automatically.

## IP Version

By default, lori uses dual-stack connections (both IPv4 and IPv6). To restrict
a client or listener to a specific protocol version, pass an
[`IPVersion`](/lori/lori-IPVersion/) parameter:

```pony
// IPv4-only listener
_tcp_listener = TCPListener(listen_auth, "127.0.0.1", "7669", this
  where ip_version = IP4)

// IPv6-only client
_tcp_connection = TCPConnection.client(auth, "::1", "7669", "", this, this
  where ip_version = IP6)
```

[`IP4`](/lori/lori-IP4/) restricts to IPv4 only,
[`IP6`](/lori/lori-IP6/) restricts to IPv6 only, and
[`DualStack`](/lori/lori-DualStack/) (the default) allows both. The same
parameter works on `ssl_client`:

```pony
_tcp_connection = TCPConnection.ssl_client(auth, sslctx, "127.0.0.1", "7669",
  "", this, this where ip_version = IP4)
```

Server-side constructors (`server`, `ssl_server`) don't need this parameter —
they accept an already-connected fd whose protocol version was determined by the
listener.

## Auth Hierarchy

Lori uses Pony's object capability model for authorization. Each operation
requires a specific auth token, and tokens form a hierarchy — a more powerful
token can create a less powerful one:

- [`NetAuth`](/lori/lori-NetAuth/) (from `AmbientAuth`) — general network access
- [`TCPAuth`](/lori/lori-TCPAuth/) (from `AmbientAuth` or `NetAuth`) — any TCP
  operation
- [`TCPListenAuth`](/lori/lori-TCPListenAuth/) (from `AmbientAuth`, `NetAuth`,
  or `TCPAuth`) — open a listener
- [`TCPConnectAuth`](/lori/lori-TCPConnectAuth/) (from `AmbientAuth`, `NetAuth`,
  or `TCPAuth`) — open a client connection
- [`TCPServerAuth`](/lori/lori-TCPServerAuth/) (from `AmbientAuth`, `NetAuth`,
  `TCPAuth`, or `TCPListenAuth`) — handle an accepted server connection

In practice, `Main` creates the auth tokens it needs from `env.root` and passes
them to the actors that need them. The echo server example above shows the
typical pattern: `Main` creates a `TCPListenAuth`, the listener creates a
`TCPServerAuth` from it, and each accepted connection receives that
`TCPServerAuth`.
"""
