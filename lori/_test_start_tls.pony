use "constrained_types"
use "files"
use "pony_test"
use "ssl/net"

class \nodoc\ iso _TestStartTLSPingPong is UnitTest
  """
  Test STARTTLS: connect plain, exchange negotiation, upgrade to TLS, then
  send encrypted data. Client sends "STARTTLS", server replies "OK" and
  upgrades, client upgrades, then client sends "Ping" over TLS and server
  echoes "Pong".
  """
  fun name(): String => "StartTLSPingPong"

  fun apply(h: TestHelper) ? =>
    let port = "9733"
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

    h.expect_action("client tls ready")
    h.expect_action("server tls ready")
    h.expect_action("client got pong")

    let listener = _TestStartTLSListener(
      port, consume sslctx, h)
    h.dispose_when_done(listener)

    h.long_test(5_000_000_000)

actor \nodoc\ _TestStartTLSClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _sslctx: SSLContext val
  let _h: TestHelper

  new create(port: String,
    sslctx: SSLContext val,
    h: TestHelper)
  =>
    _sslctx = sslctx
    _h = h

    _tcp_connection = TCPConnection.client(
      TCPConnectAuth(h.env.root),
      "localhost",
      port,
      "",
      this,
      this)
    match MakeBufferSize(2)
    | let e: BufferSize => _tcp_connection.buffer_until(e)
    end

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _tcp_connection.send("STARTTLS")

  fun ref _on_received(data: Array[U8] iso) =>
    let msg = String.from_array(consume data)
    if msg == "OK" then
      match _tcp_connection.start_tls(_sslctx, "localhost")
      | let _: StartTLSError =>
        _h.fail("Client start_tls failed")
        _h.complete(false)
      end
    elseif msg == "Pong" then
      _h.complete_action("client got pong")
    else
      _h.fail("Client got unexpected: " + msg)
    end

  fun ref _on_tls_ready() =>
    _h.complete_action("client tls ready")
    match MakeBufferSize(4)
    | let e: BufferSize => _tcp_connection.buffer_until(e)
    end
    _tcp_connection.send("Ping")

  fun ref _on_tls_failure(reason: TLSFailureReason) =>
    _h.fail("Client TLS handshake failed")

actor \nodoc\ _TestStartTLSServer
  is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _sslctx: SSLContext val
  let _h: TestHelper

  new create(sslctx: SSLContext val,
    fd: U32,
    h: TestHelper)
  =>
    _sslctx = sslctx
    _h = h

    _tcp_connection = TCPConnection.server(
      TCPServerAuth(_h.env.root),
      fd,
      this,
      this)
    match MakeBufferSize(8)
    | let e: BufferSize => _tcp_connection.buffer_until(e)
    end

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_received(data: Array[U8] iso) =>
    let msg = String.from_array(consume data)
    if msg == "STARTTLS" then
      _tcp_connection.send("OK")
      match _tcp_connection.start_tls(_sslctx)
      | let _: StartTLSError =>
        _h.fail("Server start_tls failed")
        _h.complete(false)
      end
    elseif msg == "Ping" then
      _tcp_connection.send("Pong")
    else
      _h.fail("Server got unexpected: " + msg)
    end

  fun ref _on_tls_ready() =>
    _h.complete_action("server tls ready")
    match MakeBufferSize(4)
    | let e: BufferSize => _tcp_connection.buffer_until(e)
    end

  fun ref _on_tls_failure(reason: TLSFailureReason) =>
    _h.fail("Server TLS handshake failed")

actor \nodoc\ _TestStartTLSListener is TCPListenerActor
  let _port: String
  let _sslctx: SSLContext val
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _client: (_TestStartTLSClient | None) = None

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

  fun ref _on_accept(fd: U32): _TestStartTLSServer =>
    _TestStartTLSServer(_sslctx, fd, _h)

  fun ref _on_closed() =>
    try
      (_client as _TestStartTLSClient).dispose()
    end

  fun ref _on_listening() =>
    _client = _TestStartTLSClient(
      _port, _sslctx, _h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestStartTLSListener")

class \nodoc\ iso _TestStartTLSPreconditions is UnitTest
  """
  Test that start_tls() returns the correct error for each precondition
  violation: not connected, already TLS, and not ready (muted).
  """
  fun name(): String => "StartTLSPreconditions"

  fun apply(h: TestHelper) ? =>
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

    h.expect_action("not connected verified")
    h.expect_action("already tls verified")
    h.expect_action("not ready verified")

    let listener = _TestStartTLSPreconditionsListener(
      consume sslctx, h)
    h.dispose_when_done(listener)

    h.long_test(5_000_000_000)

actor \nodoc\ _TestStartTLSPreconditionsNotConnectedClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  """
  Tests StartTLSNotConnected by calling start_tls on a closed connection.
  """
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _sslctx: SSLContext val
  let _h: TestHelper

  new create(port: String,
    sslctx: SSLContext val,
    h: TestHelper)
  =>
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
    _tcp_connection.close()
    match _tcp_connection.start_tls(_sslctx)
    | StartTLSNotConnected =>
      _h.complete_action("not connected verified")
    else
      _h.fail("Expected StartTLSNotConnected")
    end

actor \nodoc\ _TestStartTLSPreconditionsAlreadyTLSClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  """
  Tests StartTLSAlreadyTLS by calling start_tls on a connection that already
  has an SSL session. Connects plain, calls start_tls (which sets _ssl), then
  immediately calls start_tls again to get StartTLSAlreadyTLS.
  """
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _sslctx: SSLContext val
  let _h: TestHelper

  new create(port: String,
    sslctx: SSLContext val,
    h: TestHelper)
  =>
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
    // First start_tls sets _ssl
    match _tcp_connection.start_tls(_sslctx, "localhost")
    | None =>
      // _ssl is now set, second call should fail
      match _tcp_connection.start_tls(_sslctx, "localhost")
      | StartTLSAlreadyTLS =>
        _h.complete_action("already tls verified")
      else
        _h.fail("Expected StartTLSAlreadyTLS on second call")
      end
    else
      _h.fail("First start_tls should have succeeded")
    end

actor \nodoc\ _TestStartTLSPreconditionsNotReadyClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  """
  Tests StartTLSNotReady by calling start_tls on a muted connection.
  """
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _sslctx: SSLContext val
  let _h: TestHelper

  new create(port: String,
    sslctx: SSLContext val,
    h: TestHelper)
  =>
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
    _tcp_connection.mute()
    match _tcp_connection.start_tls(_sslctx)
    | StartTLSNotReady =>
      _h.complete_action("not ready verified")
    else
      _h.fail("Expected StartTLSNotReady")
    end

actor \nodoc\ _TestStartTLSPreconditionsListener is TCPListenerActor
  let _sslctx: SSLContext val
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _not_connected_client:
    (_TestStartTLSPreconditionsNotConnectedClient | None) = None
  var _already_tls_client:
    (_TestStartTLSPreconditionsAlreadyTLSClient | None) = None
  var _not_ready_client:
    (_TestStartTLSPreconditionsNotReadyClient | None) = None

  new create(sslctx: SSLContext val, h: TestHelper) =>
    _sslctx = sslctx
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(_h.env.root),
      "localhost",
      "9734",
      this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestDoNothingServerActor =>
    _TestDoNothingServerActor(fd, _h)

  fun ref _on_closed() =>
    try
      (_not_connected_client
        as _TestStartTLSPreconditionsNotConnectedClient).dispose()
    end
    try
      (_already_tls_client
        as _TestStartTLSPreconditionsAlreadyTLSClient).dispose()
    end
    try
      (_not_ready_client
        as _TestStartTLSPreconditionsNotReadyClient).dispose()
    end

  fun ref _on_listening() =>
    let port = "9734"
    _not_connected_client =
      _TestStartTLSPreconditionsNotConnectedClient(port, _sslctx, _h)
    _already_tls_client =
      _TestStartTLSPreconditionsAlreadyTLSClient(port, _sslctx, _h)
    _not_ready_client =
      _TestStartTLSPreconditionsNotReadyClient(port, _sslctx, _h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestStartTLSPreconditionsListener")

class \nodoc\ iso _TestStartTLSSendDuringUpgrade is UnitTest
  """
  Test that send() returns SendErrorNotConnected during a TLS upgrade
  handshake (state: _TLSUpgrading). After start_tls() succeeds, the
  connection is in _TLSUpgrading where sends_allowed() = false.
  """
  fun name(): String => "StartTLSSendDuringUpgrade"

  fun apply(h: TestHelper) ? =>
    let port = "9760"
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

    h.expect_action("send blocked during upgrade")

    let listener = _TestStartTLSSendDuringUpgradeListener(
      port, consume sslctx, h)
    h.dispose_when_done(listener)

    h.long_test(5_000_000_000)

actor \nodoc\ _TestStartTLSSendDuringUpgradeClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _sslctx: SSLContext val
  let _h: TestHelper

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
    // Initiate TLS upgrade
    match _tcp_connection.start_tls(_sslctx, "localhost")
    | None =>
      // Now in _TLSUpgrading — send() should fail
      match \exhaustive\ _tcp_connection.send("should fail")
      | SendErrorNotConnected =>
        _h.complete_action("send blocked during upgrade")
      | let _: SendToken =>
        _h.fail("send() should not return SendToken during TLS upgrade")
      | let _: SendError =>
        _h.fail("Expected SendErrorNotConnected, got other SendError")
      end
    | let _: StartTLSError =>
      _h.fail("start_tls should have succeeded")
    end

actor \nodoc\ _TestStartTLSSendDuringUpgradeListener is TCPListenerActor
  let _port: String
  let _sslctx: SSLContext val
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _client: (_TestStartTLSSendDuringUpgradeClient | None) = None

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
    _TestDoNothingServerActor(fd, _h)

  fun ref _on_closed() =>
    try
      (_client as _TestStartTLSSendDuringUpgradeClient).dispose()
    end

  fun ref _on_listening() =>
    _client = _TestStartTLSSendDuringUpgradeClient(
      _port, _sslctx, _h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestStartTLSSendDuringUpgradeListener")

class \nodoc\ iso _TestStartTLSHandshakeFailure is UnitTest
  """
  Test that a TLS upgrade handshake failure fires `_on_tls_failure` followed
  by `_on_closed` via `_hard_close_tls_upgrading`. Client initiates STARTTLS,
  the server replies "OK" and sends garbage instead of doing the TLS
  handshake, causing the client's TLS upgrade to fail.
  """
  fun name(): String => "StartTLSHandshakeFailure"

  fun apply(h: TestHelper) ? =>
    let port = "9761"
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

    h.expect_action("tls failure received")
    h.expect_action("on closed received")

    let listener = _TestStartTLSHandshakeFailureListener(
      port, consume sslctx, h)
    h.dispose_when_done(listener)

    h.long_test(5_000_000_000)

actor \nodoc\ _TestStartTLSHandshakeFailureClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  """
  Plaintext client that negotiates STARTTLS, then upgrades. The server sends
  garbage after "OK", so the TLS handshake fails.
  """
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _sslctx: SSLContext val
  let _h: TestHelper

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
    match MakeBufferSize(2)
    | let e: BufferSize => _tcp_connection.buffer_until(e)
    end

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _tcp_connection.send("STARTTLS")

  fun ref _on_received(data: Array[U8] iso) =>
    let msg = String.from_array(consume data)
    if msg == "OK" then
      match _tcp_connection.start_tls(_sslctx, "localhost")
      | let _: StartTLSError =>
        _h.fail("Client start_tls should have succeeded")
      end
    else
      _h.fail("Client got unexpected: " + msg)
    end

  fun ref _on_tls_ready() =>
    _h.fail("TLS handshake should not have succeeded")

  fun ref _on_tls_failure(reason: TLSFailureReason) =>
    _h.complete_action("tls failure received")

  fun ref _on_closed() =>
    _h.complete_action("on closed received")

actor \nodoc\ _TestStartTLSHandshakeFailureServer
  is (TCPConnectionActor & ServerLifecycleEventReceiver)
  """
  Plaintext server that responds to "STARTTLS" with "OK", waits for the
  client's ClientHello (which arrives as binary data), then sends garbage
  to break the TLS handshake. The wait ensures "OK" is consumed by the
  client before garbage arrives, avoiding a `StartTLSHasBufferedData`
  precondition failure (CVE-2021-23222 check).
  """
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper
  var _awaiting_client_hello: Bool = false

  new create(fd: U32, h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.server(
      TCPServerAuth(_h.env.root),
      fd,
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_received(data: Array[U8] iso) =>
    if _awaiting_client_hello then
      // Client sent a ClientHello — respond with garbage to break the
      // handshake.
      _tcp_connection.send("XXXXXXXXXX")
      _tcp_connection.close()
    else
      let msg = String.from_array(consume data)
      if msg == "STARTTLS" then
        _tcp_connection.send("OK")
        _awaiting_client_hello = true
      end
    end

actor \nodoc\ _TestStartTLSHandshakeFailureListener is TCPListenerActor
  let _port: String
  let _sslctx: SSLContext val
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _client: (_TestStartTLSHandshakeFailureClient | None) = None

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

  fun ref _on_accept(fd: U32): _TestStartTLSHandshakeFailureServer =>
    _TestStartTLSHandshakeFailureServer(fd, _h)

  fun ref _on_closed() =>
    try
      (_client as _TestStartTLSHandshakeFailureClient).dispose()
    end

  fun ref _on_listening() =>
    _client = _TestStartTLSHandshakeFailureClient(
      _port, _sslctx, _h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestStartTLSHandshakeFailureListener")
