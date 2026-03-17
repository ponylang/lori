# Examples

Ordered from simplest to most involved. The plain TCP examples come first; the SSL variants follow.

## [echo-server](echo-server/)

Minimal lori server. Shows the `TCPListenerActor` + `TCPConnectionActor` + `ServerLifecycleEventReceiver` pattern: accept a connection, receive data, send it back. Start here to understand how lori's pieces fit together.

## [ip-version](ip-version/)

IPv4-only echo server with a built-in client. Shows how to use the `ip_version` parameter on both `TCPListener` and `TCPConnection.client` to restrict connections to a specific protocol version. The same approach works with `IP6` for IPv6-only connections.

## [infinite-ping-pong](infinite-ping-pong/)

Client and server exchanging messages in a loop. Adds a `ClientLifecycleEventReceiver` client that connects, sends "Ping", and responds to every "Pong" — showing both sides of a TCP conversation.

## [framed-protocol](framed-protocol/)

Length-prefixed message framing with `expect()`. Each message has a 4-byte big-endian length header followed by a variable-length payload. Both sides use `expect()` to switch between reading the header and reading the payload, demonstrating how to build a protocol parser on top of lori's read chunking.

## [idle-timeout](idle-timeout/)

Server that closes connections after 10 seconds of inactivity. Demonstrates
`idle_timeout()` for setting a per-connection timer and `_on_idle_timeout()`
for handling the expiration — no extra actors or shared timers needed.

## [connection-timeout](connection-timeout/)

Client that connects to a non-routable address (192.0.2.1, RFC 5737 TEST-NET-1) with a 3-second connection timeout. Demonstrates `MakeConnectionTimeout`, the `connection_timeout` constructor parameter, and exhaustive matching on `ConnectionFailureReason` in `_on_connection_failure`.

## [timer](timer/)

Query-timeout simulation using `set_timer()`. A client connects, sends a "query", and sets a 3-second timer. The server never responds. When the timer fires, `_on_timer()` logs the timeout and closes the connection. Shows how `set_timer()` fires unconditionally regardless of I/O activity, unlike `idle_timeout()` which resets on every send/receive.

## [backpressure](backpressure/)

Handling `send()` errors and throttle/unthrottle callbacks. A flood client sends 200 chunks of 64KB as fast as possible, demonstrating what happens when the OS send buffer fills: `send()` returns `SendErrorNotWriteable`, `_on_throttled` fires, and the client waits for `_on_unthrottled` to resume. Also shows `_on_sent` for tracking write completion.

## [yield-read](yield-read/)

Cooperative scheduler fairness with `yield_read()`. A flood client sends 100 four-byte messages and the server yields the read loop every 10 messages, letting other actors run before reading resumes automatically. Shows how to prevent a single connection from monopolizing the scheduler without the persistent pause of `mute()`/`unmute()`.

## [socket-options](socket-options/)

Socket option tuning with dedicated convenience methods (`set_nodelay()`, `set_so_rcvbuf()`, `get_so_rcvbuf()`) and the general-purpose `setsockopt_u32()`/`getsockopt_u32()` interface. A server disables Nagle's algorithm and sets OS buffer sizes on each accepted connection, then reads back the actual values (the OS may round up). Shows both approaches to configuring TCP socket options on a live connection.

## [read-buffer-size](read-buffer-size/)

Configurable read buffer sizing with two phases. A server starts with a small 128-byte buffer for a control phase, then switches to an 8192-byte buffer for bulk transfer after receiving a command. Demonstrates `set_read_buffer_minimum()` and `resize_read_buffer()` for tuning buffer allocation at runtime, and the `read_buffer_size` constructor parameter for setting the initial size.

## [net-ssl-echo-server](net-ssl-echo-server/)

SSL version of the echo server. Demonstrates how to set up an `SSLContext` and use `TCPConnection.ssl_server` — the only change from the plain echo server is the constructor call and SSL context setup.

## [net-ssl-infinite-ping-pong](net-ssl-infinite-ping-pong/)

SSL version of infinite ping-pong. Shows both `TCPConnection.ssl_server` and `TCPConnection.ssl_client` in the same example.

## [starttls-ping-pong](starttls-ping-pong/)

STARTTLS upgrade from plaintext to TLS mid-connection. The client connects over plain TCP, negotiates a TLS upgrade, and then exchanges Ping/Pong messages over the encrypted connection. Shows `start_tls()` on both client and server, `_on_tls_ready` for post-handshake notification, and the negotiation pattern used by protocols like PostgreSQL and SMTP.
