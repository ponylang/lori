# Examples

Ordered from simplest to most involved. The plain TCP examples come first; the SSL variants follow.

## [echo-server](echo-server/)

Minimal lori server. Shows the `TCPListenerActor` + `TCPConnectionActor` + `ServerLifecycleEventReceiver` pattern: accept a connection, receive data, send it back. Start here to understand how lori's pieces fit together.

## [infinite-ping-pong](infinite-ping-pong/)

Client and server exchanging messages in a loop. Adds a `ClientLifecycleEventReceiver` client that connects, sends "Ping", and responds to every "Pong" — showing both sides of a TCP conversation.

## [framed-protocol](framed-protocol/)

Length-prefixed message framing with `expect()`. Each message has a 4-byte big-endian length header followed by a variable-length payload. Both sides use `expect()` to switch between reading the header and reading the payload, demonstrating how to build a protocol parser on top of lori's read chunking.

## [idle-timeout](idle-timeout/)

Server that closes connections after 10 seconds of inactivity. Demonstrates
`idle_timeout()` for setting a per-connection timer and `_on_idle_timeout()`
for handling the expiration — no extra actors or shared timers needed.

## [backpressure](backpressure/)

Handling `send()` errors and throttle/unthrottle callbacks. A flood client sends 200 chunks of 64KB as fast as possible, demonstrating what happens when the OS send buffer fills: `send()` returns `SendErrorNotWriteable`, `_on_throttled` fires, and the client waits for `_on_unthrottled` to resume. Also shows `_on_sent` for tracking write completion.

## [net-ssl-echo-server](net-ssl-echo-server/)

SSL version of the echo server. Demonstrates how to set up an `SSLContext` and use `TCPConnection.ssl_server` — the only change from the plain echo server is the constructor call and SSL context setup.

## [net-ssl-infinite-ping-pong](net-ssl-infinite-ping-pong/)

SSL version of infinite ping-pong. Shows both `TCPConnection.ssl_server` and `TCPConnection.ssl_client` in the same example.

## [starttls-ping-pong](starttls-ping-pong/)

STARTTLS upgrade from plaintext to TLS mid-connection. The client connects over plain TCP, negotiates a TLS upgrade, and then exchanges Ping/Pong messages over the encrypted connection. Shows `start_tls()` on both client and server, `_on_tls_ready` for post-handshake notification, and the negotiation pattern used by protocols like PostgreSQL and SMTP.
