# Lori

A TCP networking library for Pony. Lori separates connection logic from actor scheduling — the TCP state machine lives in a plain class (`TCPConnection`) that your actor delegates to, rather than baking everything into a single actor the way the standard library's `net` package does. This gives you control over how your actor is structured while lori handles the low-level I/O.

Key features:

- Fallible sends — `send()` returns `(SendToken | SendError)` instead of silently dropping data, so the application always knows whether data was accepted
- Built-in SSL — switch from plain TCP to SSL by changing a single constructor call
- Connection limits — cap the number of concurrent connections a listener will accept
- Backpressure notifications — `_on_throttled` / `_on_unthrottled` callbacks let the application respond to socket pressure

## Status

Lori is beta quality software that will change frequently. Expect breaking changes. That said, you should feel comfortable using it in your projects.

Please note that if this library encounters a state that the programmers thought was impossible to hit, it will exit the program immediately with informational messages. Normal errors are handled in standard Pony fashion.

## Installation

- Install [corral](https://github.com/ponylang/corral)
- `corral add github.com/ponylang/lori.git --version 0.8.3`
- `corral fetch` to fetch your dependencies
- `use "lori"` to include this package
- `corral run -- ponyc` to compile your application

Note: The ssl transitive dependency requires a C SSL library to be installed. Please see the ssl installation instructions for more information.

## Usage

To build a TCP application with lori, you implement an actor that mixes in `TCPConnectionActor` (which wires up the ASIO event plumbing) and a lifecycle event receiver (`ServerLifecycleEventReceiver` or `ClientLifecycleEventReceiver`) that delivers callbacks like `_on_received`, `_on_connected`, and `_on_closed`.

Here is a minimal echo server:

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

More examples are available in the [examples](examples/) directory. See the API documentation for details on the send system, SSL, connection limits, and the auth hierarchy.

## API Documentation

[https://ponylang.github.io/lori/](https://ponylang.github.io/lori/)
