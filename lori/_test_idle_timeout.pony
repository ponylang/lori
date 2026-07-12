use "constrained_types"
use "files"
use "pony_test"
use "ssl/net"
use "time"

class \nodoc\ iso _TestIdleTimeout is UnitTest
  """
  Test that the idle timeout fires when no data is sent or received.
  Server sets a 5-second idle timeout; client connects but sends nothing.
  """
  fun name(): String => "IdleTimeout"

  fun apply(h: TestHelper) =>
    let listener = _TestIdleTimeoutListener(h)
    h.dispose_when_done(listener)

    h.long_test(15_000_000_000)

actor \nodoc\ _TestIdleTimeoutListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _client: (_TestIdleTimeoutClient | None) = None

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(_h.env.root),
      "localhost",
      "7897",
      this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestIdleTimeoutServer =>
    _TestIdleTimeoutServer(fd, _h)

  fun ref _on_closed() =>
    try (_client as _TestIdleTimeoutClient).dispose() end

  fun ref _on_listening() =>
    _client = _TestIdleTimeoutClient(_h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestIdleTimeoutListener")

actor \nodoc\ _TestIdleTimeoutClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.client(
      TCPConnectAuth(_h.env.root),
      "localhost",
      "7897",
      "",
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

actor \nodoc\ _TestIdleTimeoutServer
  is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(fd: U32, h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.server(
      TCPServerAuth(_h.env.root),
      fd,
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_started() =>
    match MakeIdleTimeout(5_000)
    | let t: IdleTimeout =>
      _tcp_connection.idle_timeout(t)
    end

  fun ref _on_idle_timeout() =>
    _h.complete(true)

class \nodoc\ iso _TestIdleTimeoutReset is UnitTest
  """
  Test that I/O activity resets the idle timer. Server sets a 5-second idle
  timeout. Client sends data at 2-second intervals for 4 rounds (0s, 2s, 4s,
  6s). The sending period extends past the 5-second timeout window, so without
  the reset on receive, the timer would fire mid-stream. The timeout should
  only fire after the client stops — around 6s + 5s = 11s.
  """
  fun name(): String => "IdleTimeoutReset"

  fun apply(h: TestHelper) =>
    h.expect_action("data received")
    h.expect_action("idle timeout fired")

    let listener = _TestIdleTimeoutResetListener(h)
    h.dispose_when_done(listener)

    h.long_test(30_000_000_000)

actor \nodoc\ _TestIdleTimeoutResetListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _client: (_TestIdleTimeoutResetClient | None) = None

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(_h.env.root),
      "localhost",
      "7898",
      this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestIdleTimeoutResetServer =>
    _TestIdleTimeoutResetServer(fd, _h)

  fun ref _on_closed() =>
    try (_client as _TestIdleTimeoutResetClient).dispose() end

  fun ref _on_listening() =>
    _client = _TestIdleTimeoutResetClient(_h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestIdleTimeoutResetListener")

actor \nodoc\ _TestIdleTimeoutResetClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper
  let _timers: Timers = Timers
  var _sends_remaining: U32 = 4

  new create(h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.client(
      TCPConnectAuth(_h.env.root),
      "localhost",
      "7898",
      "",
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _tcp_connection.send("ping")
    _sends_remaining = _sends_remaining - 1
    _schedule_next_send()

  fun ref _schedule_next_send() =>
    if _sends_remaining > 0 then
      let client: _TestIdleTimeoutResetClient tag = this
      let timer = Timer(
        _TestIdleTimeoutResetTimerNotify(client),
        2_000_000_000,
        0)
      _timers(consume timer)
    end

  be _send_ping() =>
    _tcp_connection.send("ping")
    _sends_remaining = _sends_remaining - 1
    _schedule_next_send()

  be dispose() =>
    _timers.dispose()
    _tcp_connection.close()

actor \nodoc\ _TestIdleTimeoutResetServer
  is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper
  var _received_count: U32 = 0

  new create(fd: U32, h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.server(
      TCPServerAuth(_h.env.root),
      fd,
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_started() =>
    match MakeIdleTimeout(5_000)
    | let t: IdleTimeout =>
      _tcp_connection.idle_timeout(t)
    end

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    _received_count = _received_count + 1
    if _received_count == 4 then
      _h.complete_action("data received")
    end
    KeepReading

  fun ref _on_idle_timeout() =>
    _h.assert_true(_received_count == 4,
      "idle timeout fired before all data received")
    _h.complete_action("idle timeout fired")

class \nodoc\ _TestIdleTimeoutResetTimerNotify is TimerNotify
  let _client: _TestIdleTimeoutResetClient tag

  new iso create(client: _TestIdleTimeoutResetClient tag) =>
    _client = client

  fun ref apply(timer: Timer, count: U64): Bool =>
    _client._send_ping()
    false

class \nodoc\ iso _TestIdleTimeoutDisable is UnitTest
  """
  Test that calling `idle_timeout(None)` disables the timer. Server sets a
  5-second idle timeout, then immediately disables it. A watchdog timer
  completes the test after 10 seconds — if _on_idle_timeout fires, the
  test fails.
  """
  fun name(): String => "IdleTimeoutDisable"

  fun apply(h: TestHelper) =>
    let listener = _TestIdleTimeoutDisableListener(h)
    h.dispose_when_done(listener)

    h.long_test(30_000_000_000)

actor \nodoc\ _TestIdleTimeoutDisableListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _client: (_TestIdleTimeoutDisableClient | None) = None

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(_h.env.root),
      "localhost",
      "7899",
      this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestIdleTimeoutDisableServer =>
    _TestIdleTimeoutDisableServer(fd, _h)

  fun ref _on_closed() =>
    try (_client as _TestIdleTimeoutDisableClient).dispose() end

  fun ref _on_listening() =>
    _client = _TestIdleTimeoutDisableClient(_h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestIdleTimeoutDisableListener")

actor \nodoc\ _TestIdleTimeoutDisableClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.client(
      TCPConnectAuth(_h.env.root),
      "localhost",
      "7899",
      "",
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

actor \nodoc\ _TestIdleTimeoutDisableServer
  is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper
  let _timers: Timers = Timers

  new create(fd: U32, h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.server(
      TCPServerAuth(_h.env.root),
      fd,
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_started() =>
    match MakeIdleTimeout(5_000)
    | let t: IdleTimeout =>
      _tcp_connection.idle_timeout(t)
    end
    _tcp_connection.idle_timeout(None)
    // Watchdog: complete the test after 10 seconds. If _on_idle_timeout
    // fires before then, the test fails.
    let server: _TestIdleTimeoutDisableServer tag = this
    let timer = Timer(
      _TestIdleTimeoutDisableWatchdog(server),
      10_000_000_000,
      0)
    _timers(consume timer)

  fun ref _on_idle_timeout() =>
    _h.fail("_on_idle_timeout fired after being disabled")
    _h.complete(false)

  be _watchdog_complete() =>
    _h.complete(true)

  be dispose() =>
    _timers.dispose()
    _tcp_connection.close()

class \nodoc\ _TestIdleTimeoutDisableWatchdog is TimerNotify
  let _server: _TestIdleTimeoutDisableServer tag

  new iso create(server: _TestIdleTimeoutDisableServer tag) =>
    _server = server

  fun ref apply(timer: Timer, count: U64): Bool =>
    _server._watchdog_complete()
    false

class \nodoc\ iso _TestSSLIdleTimeout is UnitTest
  """
  Test that the idle timeout fires on an SSL connection when no data is sent
  or received. SSL server sets a 5-second idle timeout in _on_started();
  SSL client connects but sends nothing.
  """
  fun name(): String => "SSLIdleTimeout"

  fun apply(h: TestHelper) ? =>
    let sslctx =
      recover
        SSLContext
          .> set_authority(
            FilePath(FileAuth(h.env.root), "assets/cert.pem"))?
          .> set_cert(
            FilePath(FileAuth(h.env.root), "assets/cert.pem"),
            FilePath(FileAuth(h.env.root), "assets/key.pem"))?
          .> set_client_verify(false)
          .> set_server_verify(false)
      end

    let listener = _TestSSLIdleTimeoutListener(consume sslctx, h)
    h.dispose_when_done(listener)

    h.long_test(15_000_000_000)

actor \nodoc\ _TestSSLIdleTimeoutListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _sslctx: SSLContext val
  let _h: TestHelper
  var _client: (_TestSSLIdleTimeoutClient | None) = None

  new create(sslctx: SSLContext val, h: TestHelper) =>
    _sslctx = sslctx
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(_h.env.root),
      "localhost",
      "9743",
      this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestSSLIdleTimeoutServer =>
    _TestSSLIdleTimeoutServer(_sslctx, fd, _h)

  fun ref _on_closed() =>
    try (_client as _TestSSLIdleTimeoutClient).dispose() end

  fun ref _on_listening() =>
    _client = _TestSSLIdleTimeoutClient(_sslctx, _h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestSSLIdleTimeoutListener")

actor \nodoc\ _TestSSLIdleTimeoutClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(sslctx: SSLContext val, h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.ssl_client(
      TCPConnectAuth(_h.env.root),
      sslctx,
      "localhost",
      "9743",
      "",
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

actor \nodoc\ _TestSSLIdleTimeoutServer
  is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(sslctx: SSLContext val, fd: U32, h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.ssl_server(
      TCPServerAuth(_h.env.root),
      sslctx,
      fd,
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_started() =>
    match MakeIdleTimeout(5_000)
    | let t: IdleTimeout =>
      _tcp_connection.idle_timeout(t)
    end

  fun ref _on_idle_timeout() =>
    _h.complete(true)

class \nodoc\ iso _TestSSLIdleTimeoutNotArmedDuringHandshake is UnitTest
  """
  Regression test for issue #235. An SSL client with an idle timeout
  configured before the handshake connects to a plain TCP server so the
  handshake stalls. The idle timer must not arm until the handshake completes,
  so the connection timeout (5s) should fire instead of the idle timeout (1s).
  """
  fun name(): String => "SSLIdleTimeoutNotArmedDuringHandshake"

  fun apply(h: TestHelper) ? =>
    let sslctx =
      recover
        SSLContext
          .> set_authority(
            FilePath(FileAuth(h.env.root), "assets/cert.pem"))?
          .> set_client_verify(false)
          .> set_server_verify(false)
      end

    let listener = _TestSSLIdleTimeoutNotArmedListener(consume sslctx, h)
    h.dispose_when_done(listener)

    h.long_test(15_000_000_000)

actor \nodoc\ _TestSSLIdleTimeoutNotArmedListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _sslctx: SSLContext val
  let _h: TestHelper
  var _client: (_TestSSLIdleTimeoutNotArmedClient | None) = None

  new create(sslctx: SSLContext val, h: TestHelper) =>
    _sslctx = sslctx
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(_h.env.root),
      "localhost",
      "9744",
      this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestSSLIdleTimeoutNotArmedServer =>
    _TestSSLIdleTimeoutNotArmedServer(fd, _h)

  fun ref _on_closed() =>
    try (_client as _TestSSLIdleTimeoutNotArmedClient).dispose() end

  fun ref _on_listening() =>
    _client = _TestSSLIdleTimeoutNotArmedClient(_sslctx, _h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestSSLIdleTimeoutNotArmedListener")

actor \nodoc\ _TestSSLIdleTimeoutNotArmedClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(sslctx: SSLContext val, h: TestHelper) =>
    _h = h
    match (MakeIdleTimeout(1_000), MakeConnectionTimeout(5_000))
    | (let it: IdleTimeout, let ct: ConnectionTimeout) =>
      _tcp_connection = TCPConnection.ssl_client(
        TCPConnectAuth(_h.env.root),
        sslctx,
        "localhost",
        "9744",
        "",
        this,
        this
        where connection_timeout = ct)
      _tcp_connection.idle_timeout(it)
    | (let _: ValidationFailure, _) =>
      _h.fail("MakeIdleTimeout(1_000) should succeed")
    | (_, let _: ValidationFailure) =>
      _h.fail("MakeConnectionTimeout(5_000) should succeed")
    end

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _h.fail("SSL handshake should not complete against plain TCP server")
    _h.complete(false)

  fun ref _on_idle_timeout() =>
    _h.fail("Idle timeout fired before SSL handshake completed")
    _h.complete(false)

  fun ref _on_connection_failure(reason: ConnectionFailureReason) =>
    match reason
    | ConnectionFailedTimeout =>
      _h.complete(true)
    else
      _h.fail("Expected ConnectionFailedTimeout, got a different reason")
      _h.complete(false)
    end

actor \nodoc\ _TestSSLIdleTimeoutNotArmedServer
  is (TCPConnectionActor & ServerLifecycleEventReceiver)
  """
  Plain TCP server (no SSL) — the SSL client's handshake will stall.
  """
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(fd: U32, h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.server(
      TCPServerAuth(_h.env.root),
      fd,
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

class \nodoc\ iso _TestSSLIdleTimeoutDeferredArm is UnitTest
  """
  Test the deferred-arm path: an SSL client configures an idle timeout
  before the connection is established, then verifies it fires after the
  handshake succeeds. The idle_timeout() value is stored before the
  connection opens, and _ssl_poll arms the timer at SSLReady.
  """
  fun name(): String => "SSLIdleTimeoutDeferredArm"

  fun apply(h: TestHelper) ? =>
    let sslctx =
      recover
        SSLContext
          .> set_authority(
            FilePath(FileAuth(h.env.root), "assets/cert.pem"))?
          .> set_cert(
            FilePath(FileAuth(h.env.root), "assets/cert.pem"),
            FilePath(FileAuth(h.env.root), "assets/key.pem"))?
          .> set_client_verify(false)
          .> set_server_verify(false)
      end

    let listener = _TestSSLIdleTimeoutDeferredArmListener(consume sslctx, h)
    h.dispose_when_done(listener)

    h.long_test(15_000_000_000)

actor \nodoc\ _TestSSLIdleTimeoutDeferredArmListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _sslctx: SSLContext val
  let _h: TestHelper
  var _client: (_TestSSLIdleTimeoutDeferredArmClient | None) = None

  new create(sslctx: SSLContext val, h: TestHelper) =>
    _sslctx = sslctx
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(_h.env.root),
      "localhost",
      "9745",
      this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestSSLIdleTimeoutDeferredArmServer =>
    _TestSSLIdleTimeoutDeferredArmServer(_sslctx, fd, _h)

  fun ref _on_closed() =>
    try (_client as _TestSSLIdleTimeoutDeferredArmClient).dispose() end

  fun ref _on_listening() =>
    _client = _TestSSLIdleTimeoutDeferredArmClient(_sslctx, _h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestSSLIdleTimeoutDeferredArmListener")

actor \nodoc\ _TestSSLIdleTimeoutDeferredArmClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(sslctx: SSLContext val, h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.ssl_client(
      TCPConnectAuth(_h.env.root),
      sslctx,
      "localhost",
      "9745",
      "",
      this,
      this)
    // Configure idle timeout before the handshake completes.
    // idle_timeout() defers arming; _ssl_poll arms at SSLReady.
    match MakeIdleTimeout(5_000)
    | let t: IdleTimeout =>
      _tcp_connection.idle_timeout(t)
    end

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_idle_timeout() =>
    _h.complete(true)

actor \nodoc\ _TestSSLIdleTimeoutDeferredArmServer
  is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(sslctx: SSLContext val, fd: U32, h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.ssl_server(
      TCPServerAuth(_h.env.root),
      sslctx,
      fd,
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

class \nodoc\ iso _TestIdleTimeoutRearms is UnitTest
  """
  Test that the idle timeout fires again on a connection that stays idle.

  Server sets a 1 second idle timeout; the client sends nothing. Completes on
  the second `_on_idle_timeout`.
  """
  fun name(): String => "IdleTimeoutRearms"

  fun apply(h: TestHelper) =>
    h.expect_action("idle timeout fired twice")

    let listener = _TestIdleTimeoutRearmsListener(h)
    h.dispose_when_done(listener)

    h.long_test(15_000_000_000)

actor \nodoc\ _TestIdleTimeoutRearmsListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _server: (_TestIdleTimeoutRearmsServer | None) = None
  var _client: (_TestIdleTimeoutRearmsClient | None) = None

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(_h.env.root),
      "localhost",
      "9784",
      this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestIdleTimeoutRearmsServer =>
    let s = _TestIdleTimeoutRearmsServer(fd, _h)
    _server = s
    s

  fun ref _on_closed() =>
    try (_client as _TestIdleTimeoutRearmsClient).dispose() end
    try (_server as _TestIdleTimeoutRearmsServer).dispose() end

  fun ref _on_listening() =>
    _client = _TestIdleTimeoutRearmsClient(_h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestIdleTimeoutRearmsListener")

actor \nodoc\ _TestIdleTimeoutRearmsClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.client(
      TCPConnectAuth(_h.env.root),
      "localhost",
      "9784",
      "",
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

actor \nodoc\ _TestIdleTimeoutRearmsServer
  is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper
  var _fires: USize = 0

  new create(fd: U32, h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.server(
      TCPServerAuth(_h.env.root),
      fd,
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_started() =>
    match MakeIdleTimeout(1_000)
    | let t: IdleTimeout =>
      _tcp_connection.idle_timeout(t)
    | let _: ValidationFailure =>
      _h.fail("MakeIdleTimeout(1_000) should succeed")
      _h.complete(false)
    end

  fun ref _on_idle_timeout() =>
    _fires = _fires + 1
    if _fires == 2 then
      _h.complete_action("idle timeout fired twice")
    end

class \nodoc\ iso _TestIdleTimeoutNoRearmDuringClosing is UnitTest
  """
  Test that a firing does not re-arm the idle timer once a graceful close has
  begun.

  Server sets a 1 second idle timeout and calls `close()` from the first
  `_on_idle_timeout`. A second fire fails; a watchdog completes the test after
  5 seconds.

  The client mutes and sends nothing, and both matter. Reading would answer the
  server's FIN and hard close it, which cancels the timer. Sending would reset
  the timer through `_read()`, behind the decision under test.
  """
  fun name(): String => "IdleTimeoutNoRearmDuringClosing"

  fun apply(h: TestHelper) =>
    let listener = _TestIdleTimeoutNoRearmListener(h)
    h.dispose_when_done(listener)

    h.long_test(20_000_000_000)

actor \nodoc\ _TestIdleTimeoutNoRearmListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _server: (_TestIdleTimeoutNoRearmServer | None) = None
  var _client: (_TestIdleTimeoutNoRearmClient | None) = None

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(_h.env.root),
      "localhost",
      "9785",
      this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestIdleTimeoutNoRearmServer =>
    let s = _TestIdleTimeoutNoRearmServer(fd, _h)
    _server = s
    s

  fun ref _on_closed() =>
    try (_client as _TestIdleTimeoutNoRearmClient).dispose() end
    try (_server as _TestIdleTimeoutNoRearmServer).dispose() end

  fun ref _on_listening() =>
    _client = _TestIdleTimeoutNoRearmClient(_h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestIdleTimeoutNoRearmListener")

actor \nodoc\ _TestIdleTimeoutNoRearmClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.client(
      TCPConnectAuth(_h.env.root),
      "localhost",
      "9785",
      "",
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    // Never read: the server's FIN goes unanswered and it stays in _Closing.
    _tcp_connection.mute()

actor \nodoc\ _TestIdleTimeoutNoRearmServer
  is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper
  let _timers: Timers = Timers
  var _fires: USize = 0
  var _done: Bool = false

  new create(fd: U32, h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.server(
      TCPServerAuth(_h.env.root),
      fd,
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_started() =>
    match MakeIdleTimeout(1_000)
    | let t: IdleTimeout =>
      _tcp_connection.idle_timeout(t)
    | let _: ValidationFailure =>
      _h.fail("MakeIdleTimeout(1_000) should succeed")
      _h.complete(false)
    end

  fun ref _on_idle_timeout() =>
    _fires = _fires + 1
    if _fires == 1 then
      _tcp_connection.close()
      let server: _TestIdleTimeoutNoRearmServer tag = this
      let timer = Timer(
        _TestIdleTimeoutNoRearmWatchdog(server),
        5_000_000_000,
        0)
      _timers(consume timer)
    else
      _h.fail("idle timer re-armed during _Closing")
      _h.complete(false)
    end

  fun ref _on_closed() =>
    // A hard close cancels the idle timer, so leaving _Closing early would make
    // a second fire impossible for the wrong reason. Only teardown gets here.
    if not _done then
      _h.fail("server must stay in _Closing for the whole watchdog window")
      _h.complete(false)
    end

  be _watchdog_complete() =>
    _done = true
    _h.complete(true)

  be dispose() =>
    _timers.dispose()
    _tcp_connection.hard_close()

class \nodoc\ _TestIdleTimeoutNoRearmWatchdog is TimerNotify
  let _server: _TestIdleTimeoutNoRearmServer tag

  new iso create(server: _TestIdleTimeoutNoRearmServer tag) =>
    _server = server

  fun ref apply(timer: Timer, count: U64): Bool =>
    _server._watchdog_complete()
    false

class \nodoc\ iso _TestIdleTimeoutRearmsDuringTLSUpgrade is UnitTest
  """
  Test that the idle timeout keeps firing during a TLS upgrade.

  Client sets a 1 second idle timeout and calls `start_tls()` against a server
  that never answers the ClientHello, so it stalls in `_TLSUpgrading`. Completes
  on the second `_on_idle_timeout`.
  """
  fun name(): String => "IdleTimeoutRearmsDuringTLSUpgrade"

  fun apply(h: TestHelper) ? =>
    let port = "9786"
    let file_auth = FileAuth(h.env.root)
    let sslctx =
      recover
        SSLContext
          .> set_authority(
            FilePath(file_auth, "assets/cert.pem"))?
          .> set_cert(
            FilePath(file_auth, "assets/cert.pem"),
            FilePath(file_auth, "assets/key.pem"))?
          .> set_client_verify(false)
          .> set_server_verify(false)
      end

    h.expect_action("idle timeout fired twice during TLS upgrade")

    let listener = _TestIdleTimeoutTLSUpgradeListener(port, consume sslctx, h)
    h.dispose_when_done(listener)

    h.long_test(15_000_000_000)

actor \nodoc\ _TestIdleTimeoutTLSUpgradeListener is TCPListenerActor
  let _port: String
  let _sslctx: SSLContext val
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _server: (_TestDoNothingServerActor | None) = None
  var _client: (_TestIdleTimeoutTLSUpgradeClient | None) = None

  new create(port: String, sslctx: SSLContext val, h: TestHelper) =>
    _port = port
    _sslctx = sslctx
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(_h.env.root),
      "localhost",
      _port,
      this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestDoNothingServerActor =>
    let s = _TestDoNothingServerActor(fd, _h)
    _server = s
    s

  fun ref _on_closed() =>
    try (_client as _TestIdleTimeoutTLSUpgradeClient).dispose() end
    try (_server as _TestDoNothingServerActor).dispose() end

  fun ref _on_listening() =>
    _client = _TestIdleTimeoutTLSUpgradeClient(_port, _sslctx, _h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestIdleTimeoutTLSUpgradeListener")

actor \nodoc\ _TestIdleTimeoutTLSUpgradeClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _sslctx: SSLContext val
  let _h: TestHelper
  var _fires: USize = 0

  new create(port: String, sslctx: SSLContext val, h: TestHelper) =>
    _sslctx = sslctx
    _h = h
    _tcp_connection = TCPConnection.client(
      TCPConnectAuth(h.env.root),
      "localhost",
      port,
      "",
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    match MakeIdleTimeout(1_000)
    | let t: IdleTimeout =>
      _tcp_connection.idle_timeout(t)
    | let _: ValidationFailure =>
      _h.fail("MakeIdleTimeout(1_000) should succeed")
      _h.complete(false)
    end
    // The server never answers, so this parks in _TLSUpgrading.
    match _tcp_connection.start_tls(_sslctx, "localhost")
    | None => None
    | let _: StartTLSError =>
      _h.fail("start_tls should have succeeded")
      _h.complete(false)
    end

  fun ref _on_connection_failure(reason: ConnectionFailureReason) =>
    _h.fail("client connect failed")

  fun ref _on_tls_ready() =>
    _h.fail("the server never answers, so the upgrade must not complete")

  fun ref _on_idle_timeout() =>
    _fires = _fires + 1
    if _fires == 2 then
      _h.complete_action("idle timeout fired twice during TLS upgrade")
    end
