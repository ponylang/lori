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
  tcp_connection.pony       -- TCPConnection class (core: read/write/connect/close)
  tcp_connection_actor.pony -- TCPConnectionActor trait (actor wrapper)
  tcp_listener.pony         -- TCPListener class (accept loop, connection limits)
  tcp_listener_actor.pony   -- TCPListenerActor trait (actor wrapper)
  lifecycle_event_receiver.pony -- Client/ServerLifecycleEventReceiver traits
  net_ssl_connection.pony   -- NetSSLClientConnection/NetSSLServerConnection (SSL layer)
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

1. **`TCPConnection`** (class) — All TCP state and I/O logic. Created with `TCPConnection.client(...)` or `TCPConnection.server(...)`. Not an actor itself.
2. **`TCPConnectionActor`** (trait) — The actor trait users implement. Requires `fun ref _connection(): TCPConnection`. Provides behaviors that delegate to the TCPConnection: `_event_notify`, `_read_again`, `dispose`, etc.
3. **Lifecycle event receivers** — `ClientLifecycleEventReceiver` / `ServerLifecycleEventReceiver` traits with callbacks: `_on_connected`, `_on_received`, `_on_closed`, `_on_send`, `_on_throttled`, etc.

### How to implement a server

```
actor MyServer is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()

  new create(auth: TCPServerAuth, fd: U32) =>
    _tcp_connection = TCPConnection.server(auth, fd, this, this)

  fun ref _connection(): TCPConnection => _tcp_connection
  fun ref _next_lifecycle_event_receiver(): None => None

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
  fun ref _next_lifecycle_event_receiver(): None => None

  fun ref _on_connected() => // connected
  fun ref _on_received(data: Array[U8] iso) => // handle data
```

### Lifecycle receiver chaining

The `_next_lifecycle_event_receiver()` method enables middleware-style wrapping. `NetSSLClientConnection`/`NetSSLServerConnection` wrap a user's receiver to intercept lifecycle events for SSL handshake/encryption. Default trait method implementations auto-delegate to the next receiver in the chain.

### Platform differences

POSIX and Windows (IOCP) have distinct code paths throughout `TCPConnection`, guarded by `ifdef posix`/`ifdef windows`. POSIX uses edge-triggered oneshot events with resubscription; Windows uses IOCP completion callbacks.

## Conventions

- Follows the [Pony standard library Style Guide](https://github.com/ponylang/ponyc/blob/main/STYLE_GUIDE.md)
- `_Unreachable()` primitive used for states the compiler can't prove impossible — prints location and exits with code 1
- `TCPConnection.none()` used as a field initializer before real initialization happens via `_finish_initialization` behavior
- Auth hierarchy: `AmbientAuth` > `NetAuth` > `TCPAuth` > `TCPListenAuth`/`TCPConnectAuth` > `TCPServerAuth`
- All lifecycle callbacks are prefixed with `_on_` (private by convention)
- Tests use hardcoded ports per test (5786, 6666, 6767, 7664, 9728, etc.)
- `\nodoc\` annotation on test classes
