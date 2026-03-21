use "constrained_types"
use "files"
use "pony_test"
use "ssl/net"

class \nodoc\ iso _TestSSLPingPong is UnitTest
  """
  Test SSL via the built-in ssl_client/ssl_server constructors.
  """
  fun name(): String => "SSLPingPong"

  fun apply(h: TestHelper) ? =>
    let port = "1417"
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

    let pings_to_send: I32 = 100

    let listener = _TestSSLPongerListener(
      port, consume sslctx, pings_to_send, h)
    h.dispose_when_done(listener)

    h.long_test(5_000_000_000)

actor \nodoc\ _TestSSLPinger
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  var _pings_to_send: I32
  let _h: TestHelper

  new create(port: String,
    sslctx: SSLContext val,
    pings_to_send: I32,
    h: TestHelper)
  =>
    _pings_to_send = pings_to_send
    _h = h

    _tcp_connection = TCPConnection.ssl_client(
      TCPConnectAuth(h.env.root),
      sslctx,
      "localhost",
      port,
      "",
      this,
      this)
    match MakeBufferSize(4)
    | let e: BufferSize => _tcp_connection.buffer_until(e)
    end

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    if _pings_to_send > 0 then
      _tcp_connection.send("Ping")
      _pings_to_send = _pings_to_send - 1
    end

  fun ref _on_received(data: Array[U8] iso) =>
    if _pings_to_send > 0 then
      _tcp_connection.send("Ping")
      _pings_to_send = _pings_to_send - 1
    elseif _pings_to_send == 0 then
      _h.complete(true)
    else
      _h.fail("Too many pongs received")
    end

actor \nodoc\ _TestSSLPonger
  is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  var _pings_to_receive: I32
  let _h: TestHelper

  new create(sslctx: SSLContext val,
    fd: U32,
    pings_to_receive: I32,
    h: TestHelper)
  =>
    _pings_to_receive = pings_to_receive
    _h = h

    _tcp_connection = TCPConnection.ssl_server(
      TCPServerAuth(_h.env.root),
      sslctx,
      fd,
      this,
      this)
    match MakeBufferSize(4)
    | let e: BufferSize => _tcp_connection.buffer_until(e)
    end

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_received(data: Array[U8] iso) =>
    if _pings_to_receive > 0 then
      _tcp_connection.send("Pong")
      _pings_to_receive = _pings_to_receive - 1
    elseif _pings_to_receive == 0 then
      _tcp_connection.send("Pong")
    else
      _h.fail("Too many pings received")
    end

actor \nodoc\ _TestSSLPongerListener is TCPListenerActor
  let _port: String
  let _sslctx: SSLContext val
  var _tcp_listener: TCPListener = TCPListener.none()
  var _pings_to_receive: I32
  let _h: TestHelper
  var _pinger: (_TestSSLPinger | None) = None

  new create(port: String,
    sslctx: SSLContext val,
    pings_to_receive: I32,
    h: TestHelper)
  =>
    _port = port
    _sslctx = sslctx
    _pings_to_receive = pings_to_receive
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(_h.env.root),
      "localhost",
      _port,
      this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestSSLPonger =>
    _TestSSLPonger(_sslctx, fd, _pings_to_receive, _h)

  fun ref _on_closed() =>
    try
      (_pinger as _TestSSLPinger).dispose()
    end

  fun ref _on_listening() =>
    _pinger = _TestSSLPinger(
      _port, _sslctx, _pings_to_receive, _h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestSSLPongerListener")

class \nodoc\ iso _TestSSLSendv is UnitTest
  """
  Test send() with multiple buffers over an SSL connection. Client sends
  multiple buffers, server verifies the received data.
  """
  fun name(): String => "SSLSendv"

  fun apply(h: TestHelper) ? =>
    let port = "7896"
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

    h.expect_action("server listening")
    h.expect_action("client connected")
    h.expect_action("data verified")
    h.expect_action("on_sent fired")

    let listener = _TestSSLSendvListener(
      port, consume sslctx, h)
    h.dispose_when_done(listener)

    h.long_test(5_000_000_000)

actor \nodoc\ _TestSSLSendvListener is TCPListenerActor
  let _port: String
  let _sslctx: SSLContext val
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _client: (_TestSSLSendvClient | None) = None

  new create(port: String,
    sslctx: SSLContext val,
    h: TestHelper)
  =>
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

  fun ref _on_accept(fd: U32): _TestSSLSendvServer =>
    _TestSSLSendvServer(_sslctx, fd, _h)

  fun ref _on_closed() =>
    try (_client as _TestSSLSendvClient).dispose() end

  fun ref _on_listening() =>
    _h.complete_action("server listening")
    _client = _TestSSLSendvClient(_port, _sslctx, _h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestSSLSendvListener")

actor \nodoc\ _TestSSLSendvClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper
  var _expected_token: (SendToken | None) = None

  new create(port: String,
    sslctx: SSLContext val,
    h: TestHelper)
  =>
    _h = h

    _tcp_connection = TCPConnection.ssl_client(
      TCPConnectAuth(h.env.root),
      sslctx,
      "localhost",
      port,
      "",
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _h.complete_action("client connected")
    match \exhaustive\ _tcp_connection.send(
      recover val [as ByteSeq: "SSL "; "Hello"; " World"] end)
    | let token: SendToken =>
      _expected_token = token
    | let _: SendError =>
      _h.fail("send() returned an error")
      _h.complete(false)
    end

  fun ref _on_sent(token: SendToken) =>
    match \exhaustive\ _expected_token
    | let expected: SendToken =>
      _h.assert_true(token == expected, "token mismatch")
      _h.complete_action("on_sent fired")
    | None =>
      _h.fail("_on_sent fired but no token was expected")
    end

actor \nodoc\ _TestSSLSendvServer
  is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(sslctx: SSLContext val,
    fd: U32,
    h: TestHelper)
  =>
    _h = h

    _tcp_connection = TCPConnection.ssl_server(
      TCPServerAuth(_h.env.root),
      sslctx,
      fd,
      this,
      this)
    match MakeBufferSize(15)
    | let e: BufferSize => _tcp_connection.buffer_until(e)
    end

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_received(data: Array[U8] iso) =>
    _h.assert_eq[String]("SSL Hello World", String.from_array(consume data))
    _h.complete_action("data verified")
    _tcp_connection.close()

class \nodoc\ iso _TestSSLHandshakeFailureClient is UnitTest
  """
  Test that an SSL client whose handshake fails (peer sends garbage) gets
  `_on_connection_failure(ConnectionFailedSSL)` via `_hard_close_ssl_handshaking`.
  """
  fun name(): String => "SSLHandshakeFailureClient"

  fun apply(h: TestHelper) ? =>
    let port = "9757"
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

    h.expect_action("client failure")

    let listener = _TestSSLHandshakeFailureClientListener(
      port, consume sslctx, h)
    h.dispose_when_done(listener)

    h.long_test(5_000_000_000)

actor \nodoc\ _TestSSLHandshakeFailureClientListener is TCPListenerActor
  """
  Plain TCP listener that accepts connections, sends garbage to break the
  SSL handshake, and closes.
  """
  let _port: String
  let _sslctx: SSLContext val
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _client: (_TestSSLHandshakeFailureSSLClient | None) = None

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

  fun ref _on_accept(fd: U32): _TestSSLHandshakeFailurePlainServer =>
    _TestSSLHandshakeFailurePlainServer(fd, _h)

  fun ref _on_closed() =>
    try (_client as _TestSSLHandshakeFailureSSLClient).dispose() end

  fun ref _on_listening() =>
    _client = _TestSSLHandshakeFailureSSLClient(
      _port, _sslctx, _h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestSSLHandshakeFailureClientListener")

actor \nodoc\ _TestSSLHandshakeFailurePlainServer
  is (TCPConnectionActor & ServerLifecycleEventReceiver)
  """
  Plain TCP server that sends garbage bytes to break the SSL handshake.
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

  fun ref _on_started() =>
    _tcp_connection.send("XXXXXXXXXX")
    _tcp_connection.close()

actor \nodoc\ _TestSSLHandshakeFailureSSLClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  """
  SSL client connecting to a plain TCP server. The handshake will fail.
  """
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(port: String, sslctx: SSLContext val, h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.ssl_client(
      TCPConnectAuth(h.env.root),
      sslctx,
      "localhost",
      port,
      "",
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _h.fail("Should not have connected")

  fun ref _on_connection_failure(reason: ConnectionFailureReason) =>
    match reason
    | ConnectionFailedSSL =>
      _h.complete_action("client failure")
    else
      _h.fail("Expected ConnectionFailedSSL")
    end

class \nodoc\ iso _TestSSLHandshakeFailureServer is UnitTest
  """
  Test that an SSL server whose handshake fails (peer sends garbage) gets
  `_on_start_failure(StartFailedSSL)` via `_hard_close_ssl_handshaking`.
  """
  fun name(): String => "SSLHandshakeFailureServer"

  fun apply(h: TestHelper) ? =>
    let port = "9758"
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

    h.expect_action("server failure")

    let listener = _TestSSLHandshakeFailureServerListener(
      port, consume sslctx, h)
    h.dispose_when_done(listener)

    h.long_test(5_000_000_000)

actor \nodoc\ _TestSSLHandshakeFailureServerListener is TCPListenerActor
  """
  Listener that creates SSL servers. A plain TCP client connects and sends
  garbage to break the SSL handshake.
  """
  let _port: String
  let _sslctx: SSLContext val
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _client: (_TestSSLHandshakeFailurePlainClient | None) = None

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

  fun ref _on_accept(fd: U32): _TestSSLHandshakeFailureSSLServer =>
    _TestSSLHandshakeFailureSSLServer(_sslctx, fd, _h)

  fun ref _on_closed() =>
    try (_client as _TestSSLHandshakeFailurePlainClient).dispose() end

  fun ref _on_listening() =>
    _client = _TestSSLHandshakeFailurePlainClient(_port, _h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestSSLHandshakeFailureServerListener")

actor \nodoc\ _TestSSLHandshakeFailureSSLServer
  is (TCPConnectionActor & ServerLifecycleEventReceiver)
  """
  SSL server that receives garbage from a plain client. The handshake fails.
  """
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
    _h.fail("Should not have started")

  fun ref _on_start_failure(reason: StartFailureReason) =>
    match reason
    | StartFailedSSL =>
      _h.complete_action("server failure")
    end

actor \nodoc\ _TestSSLHandshakeFailurePlainClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  """
  Plain TCP client that sends garbage to an SSL server.
  """
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(port: String, h: TestHelper) =>
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
    _tcp_connection.send("XXXXXXXXXX")
    _tcp_connection.close()

class \nodoc\ iso _TestSSLHandshakeCompleteTransitionsToOpen is UnitTest
  """
  Test that after a successful SSL handshake, the connection is in _Open
  state: is_open() returns true and send() returns a SendToken.
  """
  fun name(): String => "SSLHandshakeCompleteTransitionsToOpen"

  fun apply(h: TestHelper) ? =>
    let port = "9759"
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

    h.expect_action("is_open verified")
    h.expect_action("send returns token")

    let listener = _TestSSLTransitionToOpenListener(
      port, consume sslctx, h)
    h.dispose_when_done(listener)

    h.long_test(5_000_000_000)

actor \nodoc\ _TestSSLTransitionToOpenListener is TCPListenerActor
  let _port: String
  let _sslctx: SSLContext val
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _client: (_TestSSLTransitionToOpenClient | None) = None

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

  fun ref _on_accept(fd: U32): _TestSSLTransitionToOpenServer =>
    _TestSSLTransitionToOpenServer(_sslctx, fd, _h)

  fun ref _on_closed() =>
    try (_client as _TestSSLTransitionToOpenClient).dispose() end

  fun ref _on_listening() =>
    _client = _TestSSLTransitionToOpenClient(_port, _sslctx, _h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestSSLTransitionToOpenListener")

actor \nodoc\ _TestSSLTransitionToOpenClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(port: String, sslctx: SSLContext val, h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.ssl_client(
      TCPConnectAuth(h.env.root),
      sslctx,
      "localhost",
      port,
      "",
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _h.assert_true(_tcp_connection.is_open(), "is_open should be true")
    _h.complete_action("is_open verified")

    match \exhaustive\ _tcp_connection.send("test")
    | let _: SendToken =>
      _h.complete_action("send returns token")
    | let _: SendError =>
      _h.fail("send() should return SendToken")
    end
    _tcp_connection.close()

actor \nodoc\ _TestSSLTransitionToOpenServer
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

class \nodoc\ iso _TestSSLIsWriteableDuringHandshake is UnitTest
  """
  Test that is_writeable() returns false during the initial SSL handshake
  (state: _SSLHandshaking). A plain TCP client connects to an SSL server;
  the server enters _SSLHandshaking but the handshake never completes
  because the client doesn't speak TLS. The server calls check_writeable()
  on itself from its constructor; both this and _finish_initialization are
  self-sends (FIFO), so check_writeable fires after _finish_initialization
  when the server is in _SSLHandshaking.
  """
  fun name(): String => "SSLIsWriteableDuringHandshake"

  fun apply(h: TestHelper) ? =>
    let port = "9763"
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

    h.expect_action("is_writeable false during ssl handshake")

    let listener = _TestSSLIsWriteableListener(
      port, consume sslctx, h)
    h.dispose_when_done(listener)

    h.long_test(5_000_000_000)

actor \nodoc\ _TestSSLIsWriteableListener is TCPListenerActor
  let _port: String
  let _sslctx: SSLContext val
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _client: (_TestSSLIsWriteablePlainClient | None) = None
  var _server: (_TestSSLIsWriteableServer | None) = None

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

  fun ref _on_accept(fd: U32): _TestSSLIsWriteableServer =>
    let server = _TestSSLIsWriteableServer(_sslctx, fd, _h)
    _server = server
    server

  fun ref _on_closed() =>
    try (_server as _TestSSLIsWriteableServer).dispose() end
    try (_client as _TestSSLIsWriteablePlainClient).dispose() end

  fun ref _on_listening() =>
    _client = _TestSSLIsWriteablePlainClient(_port, _h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestSSLIsWriteableListener")

actor \nodoc\ _TestSSLIsWriteableServer
  is (TCPConnectionActor & ServerLifecycleEventReceiver)
  """
  SSL server whose handshake stalls because the peer is a plain TCP client.
  The constructor calls check_writeable() after creating the ssl_server
  TCPConnection; both _finish_initialization (from the TCPConnection
  constructor) and check_writeable are self-sends, so FIFO ordering
  guarantees check_writeable fires in _SSLHandshaking.
  """
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
    check_writeable()

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  be check_writeable() =>
    _h.assert_false(
      _tcp_connection.is_writeable(),
      "is_writeable should be false during SSL handshake")
    _h.complete_action("is_writeable false during ssl handshake")
    _tcp_connection.hard_close()

  fun ref _on_started() =>
    _h.fail("SSL handshake should not complete against plain TCP client")

actor \nodoc\ _TestSSLIsWriteablePlainClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  """
  Plain TCP client (no SSL) — the SSL server's handshake will stall.
  """
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(port: String, h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.client(
      TCPConnectAuth(_h.env.root),
      "localhost",
      port,
      "",
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection
