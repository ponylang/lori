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

  fun ref _on_received(data: Array[U8] iso) =>
    _tcp_connection.send(consume data)

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

  fun ref _on_connection_failure() =>
    // All connection attempts failed
    None

  fun ref _on_received(data: Array[U8] iso) =>
    // Handle response from server
    None
```

Clients use `ClientLifecycleEventReceiver` instead of
`ServerLifecycleEventReceiver`. The key difference is the connection lifecycle:
clients get `_on_connecting` (called as connection attempts are in progress),
`_on_connected` (ready for data), and `_on_connection_failure` (all attempts
failed). Servers get `_on_started` (ready for data) and `_on_start_failure`.

## Sending Data

Unlike many networking libraries, `send()` is fallible. It returns
`(SendToken | SendError)` rather than silently dropping data:

```pony
match _tcp_connection.send("some data")
| let token: SendToken =>
  // Data accepted. token will arrive in _on_sent when fully written.
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
operation. When the data has been fully handed to the OS, lori delivers the
same token to `_on_sent`. If the connection closes while a write is still
partially pending, `_on_send_failed` fires instead. Both callbacks always arrive
in a subsequent behavior turn, never during `send()` itself.

The library does not queue data during backpressure. When `send()` returns
[`SendErrorNotWriteable`](/lori/lori-SendErrorNotWriteable/), the application
decides what to do: queue, drop, or close. Use `_on_throttled` and
`_on_unthrottled` to track backpressure state, or check `is_writeable()` before
calling `send()`.

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

  fun ref _on_received(data: Array[U8] iso) =>
    _tcp_connection.send(consume data)

  fun ref _on_start_failure() =>
    // SSL handshake failed
    None
```

SSL is handled entirely inside `TCPConnection`. The handshake runs
transparently after the TCP connection is established, and `_on_connected`
(client) or `_on_started` (server) fires only after the handshake completes. If
the handshake fails, clients get `_on_connection_failure` and servers get
`_on_start_failure`. The rest of the application code (sending, receiving,
closing) is identical to the non-SSL case.

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

  fun ref _on_received(data: Array[U8] iso) =>
    let msg = String.from_array(consume data)
    if msg == "OK" then
      // Server agreed to upgrade — initiate TLS handshake
      match _tcp_connection.start_tls(_sslctx, "localhost")
      | let err: StartTLSError => None // handle error
      end
    end

  fun ref _on_tls_ready() =>
    // TLS handshake complete — now sending encrypted data
    _tcp_connection.send("encrypted payload")

  fun ref _on_tls_failure() =>
    // TLS handshake failed — _on_closed will follow
    None
```

`start_tls()` returns `None` when the handshake has been started, or a
[`StartTLSError`](/lori/lori-StartTLSError/) if the upgrade cannot proceed. The
connection must be open, not already TLS, not muted, and have no buffered read
data or pending writes. During the handshake, `send()` returns
`SendErrorNotConnected`. When the handshake completes, `_on_tls_ready()` fires.
If it fails, `_on_tls_failure()` fires followed by `_on_closed()`.

## Connection Limits

`TCPListener` accepts an optional `limit` parameter to cap the number of
concurrent connections:

```pony
// Accept at most 100 connections at a time
_tcp_listener = TCPListener(listen_auth, host, port, this, 100)
```

When the limit is reached, the listener pauses accepting. As connections close,
it resumes automatically. The default is no limit.

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
