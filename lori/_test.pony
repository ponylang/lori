use "pony_test"
use "files"
use "ssl/net"

actor \nodoc\ Main is TestList
  new create(env: Env) =>
    PonyTest(env, this)

  new make() =>
    None

  fun tag tests(test: PonyTest) =>
    test(_TestCanListen)
    test(_TestListenerLocalAddress)
    test(_TestMute)
    test(_TestOutgoingFails)
    test(_TestPingPong)
    test(_TestSSLPingPong)
    test(_TestBasicExpect)
    test(_TestUnmute)
    test(_TestSendToken)
    test(_TestSendAfterClose)
    test(_TestStartTLSPingPong)
    test(_TestStartTLSPreconditions)
    test(_TestHardCloseWhileConnecting)
    test(_TestCloseWhileConnecting)

class \nodoc\ iso _TestOutgoingFails is UnitTest
  """
  Test that we get a failure callback when an outgoing connection fails
  """
  fun name(): String => "OutgoingFails"

  fun apply(h: TestHelper) =>
    let client = _TestOutgoingFailure(h)
    h.dispose_when_done(client)

    h.long_test(5_000_000_000)

actor \nodoc\ _TestOutgoingFailure is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    _tcp_connection = TCPConnection.client(
      TCPConnectAuth(_h.env.root),
      host,
      "3245",
      "",
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _h.fail("_on_connected for a connection that should have failed")
    _h.complete(false)

  fun ref _on_connection_failure() =>
    _h.complete(true)

class \nodoc\ iso _TestPingPong is UnitTest
  """
  Test sending and receiving via a simple Ping-Pong application
  """
  fun name(): String => "PingPong"

  fun apply(h: TestHelper) =>
    let port = "7664"
    let pings_to_send: I32 = 100

    let listener = _TestPongerListener(port, pings_to_send, h)
    h.dispose_when_done(listener)

    h.long_test(5_000_000_000)

actor \nodoc\ _TestPinger is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  var _pings_to_send: I32
  let _h: TestHelper

  new create(port: String,
    pings_to_send: I32,
    h: TestHelper)
  =>
    _pings_to_send = pings_to_send
    _h = h

    _tcp_connection = TCPConnection.client(
      TCPConnectAuth(h.env.root),
      "localhost",
      port,
      "",
      this,
      this)
    try _tcp_connection.expect(4)? end

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

actor \nodoc\ _TestPonger is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  var _pings_to_receive: I32
  let _h: TestHelper

  new create(fd: U32,
    pings_to_receive: I32,
    h: TestHelper)
  =>
    _pings_to_receive = pings_to_receive
    _h = h

    _tcp_connection = TCPConnection.server(
      TCPServerAuth(_h.env.root),
      fd,
      this,
      this)
    try _tcp_connection.expect(4)? end

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

actor \nodoc\ _TestPongerListener is TCPListenerActor
  let _port: String
  var _tcp_listener: TCPListener = TCPListener.none()
  var _pings_to_receive: I32
  let _h: TestHelper
  var _pinger: (_TestPinger | None) = None

  new create(port: String,
    pings_to_receive: I32,
    h: TestHelper)
  =>
    _port = port
    _pings_to_receive = pings_to_receive
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(_h.env.root),
      "localhost",
      _port,
      this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestPonger =>
    _TestPonger(fd, _pings_to_receive, _h)

  fun ref _on_closed() =>
    try
      (_pinger as _TestPinger).dispose()
    end

  fun ref _on_listening() =>
    _pinger = _TestPinger(_port, _pings_to_receive, _h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestPongerListener")

class \nodoc\ iso _TestBasicExpect is UnitTest
  fun name(): String => "BasicExpect"

  fun apply(h: TestHelper) =>
    h.expect_action("server listening")
    h.expect_action("client connected")
    h.expect_action("expected data received")

    let s = _TestBasicExpectListener(h)

    h.dispose_when_done(s)

    h.long_test(5_000_000_000)

actor \nodoc\ _TestBasicExpectClient is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.client(
      TCPConnectAuth(_h.env.root),
      "localhost",
      "9728",
      "",
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _h.complete_action("client connected")
    _tcp_connection.send("hi there, how are you???")

  fun ref _on_received(data: Array[U8] iso) =>
    _h.fail("Client shouldn't get data")

actor \nodoc\ _TestBasicExpectListener is TCPListenerActor
  let _h: TestHelper
  var _tcp_listener: TCPListener = TCPListener.none()
  var _client: (_TestBasicExpectClient | None) = None

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(_h.env.root),
      "localhost",
      "9728",
      this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestBasicExpectServer =>
    _TestBasicExpectServer(fd, _h)

  fun ref _on_closed() =>
    try (_client as _TestBasicExpectClient).dispose() end

  fun ref _on_listening() =>
    _h.complete_action("server listening")
    _client =_TestBasicExpectClient(_h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestBasicExpectListener")

actor \nodoc\ _TestBasicExpectServer is (TCPConnectionActor & ServerLifecycleEventReceiver)
  let _h: TestHelper
  var _tcp_connection: TCPConnection = TCPConnection.none()
  var _received_count: U8 = 0

  new create(fd: U32, h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.server(
      TCPServerAuth(_h.env.root),
      fd,
      this,
      this)
    try _tcp_connection.expect(4)? end

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_received(data: Array[U8] iso) =>
    _received_count = _received_count + 1

    if _received_count == 1 then
      _h.assert_eq[String]("hi t", String.from_array(consume data))
    elseif _received_count == 2 then
      _h.assert_eq[String]("here", String.from_array(consume data))
    elseif _received_count == 3 then
      _h.assert_eq[String](", ho", String.from_array(consume data))
    elseif _received_count == 4 then
      _h.assert_eq[String]("w ar", String.from_array(consume data))
    elseif _received_count == 5 then
      _h.assert_eq[String]("e yo", String.from_array(consume data))
    elseif _received_count == 6 then
      _h.assert_eq[String]("u???", String.from_array(consume data))
      _h.complete_action("expected data received")
      _tcp_connection.close()
    end

class \nodoc\ iso _TestCanListen is UnitTest
  """
  Test that we can listen on a socket for incoming connections and that the
  `_on_listening` callback is correctly called.
  """
  fun name(): String => "CanListen"

  fun apply(h: TestHelper) =>
    let listener = _TestCanListenListener(h)
    h.dispose_when_done(listener)

    h.long_test(5_000_000_000)

actor \nodoc\ _TestCanListenListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(_h.env.root),
      "localhost",
      "5786",
      this)

  fun ref _on_accept(fd: U32): _TestDoNothingServerActor =>
    _h.fail("_on_accept shouldn't be called")
    _h.complete(false)
    _TestDoNothingServerActor(fd, _h)

  fun ref _on_listen_failure() =>
    _h.fail("listening failed")
    _h.complete(false)

  fun ref _on_listening() =>
    _h.complete(true)

  fun ref _listener(): TCPListener =>
    _tcp_listener

actor \nodoc\ _TestDoNothingServerActor is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()

  new create(fd: U32, h: TestHelper) =>
    _tcp_connection = TCPConnection.server(
      TCPServerAuth(h.env.root),
      fd,
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

class \nodoc\ iso _TestListenerLocalAddress is UnitTest
  """
  Test that `local_address()` on a listener returns the actual bound address.
  Binds to port "0" (OS-assigned) and verifies the reported port is non-zero.
  """
  fun name(): String => "ListenerLocalAddress"

  fun apply(h: TestHelper) =>
    let listener = _TestListenerLocalAddressListener(h)
    h.dispose_when_done(listener)

    h.long_test(5_000_000_000)

actor \nodoc\ _TestListenerLocalAddressListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(_h.env.root),
      "localhost",
      "0",
      this)

  fun ref _on_accept(fd: U32): _TestDoNothingServerActor =>
    _h.fail("_on_accept shouldn't be called")
    _h.complete(false)
    _TestDoNothingServerActor(fd, _h)

  fun ref _on_listen_failure() =>
    _h.fail("listening failed")
    _h.complete(false)

  fun ref _on_listening() =>
    let addr = _listener().local_address()
    _h.assert_true(addr.port() > 0)
    _h.complete(true)

  fun ref _listener(): TCPListener =>
    _tcp_listener

 class \nodoc\ iso _TestMute is UnitTest
  """
  Test that the `mute` behavior stops us from reading incoming data. The
  test assumes that send/recv works correctly and that the absence of
  data received is because we muted the connection.

  Test works as follows:

  Once an incoming connection is established, we set mute on it and then
  verify that within a 2 second long test that the `_on_received` callback is
  not triggered. A timeout is considering passing and `_on_received` being called
  is grounds for a failure.
  """
  fun name(): String => "TestMute"

  fun ref apply(h: TestHelper) =>
    h.expect_action("server listen")
    h.expect_action("client create")
    h.expect_action("server accept")
    h.expect_action("server started")
    h.expect_action("client connected")
    h.expect_action("server muted")
    h.expect_action("server asks for data")
    h.expect_action("client sent data")

    let s = _TestMuteListener(h)
    h.dispose_when_done(s)

    h.long_test(5_000_000_000)

  fun timed_out(h: TestHelper) =>
    h.complete(true)

actor \nodoc\ _TestMuteListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _server: (_TestMuteServer | None) = None
  var _client: (_TestMuteClient | None) = None

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(_h.env.root),
      "localhost",
      "6666",
      this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestMuteServer =>
    _h.complete_action("server accept")
    let s = _TestMuteServer(fd, _h)
    _server = s
    s

  fun ref _on_listen_failure() =>
    _h.fail_action("server listen")
    _h.complete(false)

  fun ref _on_listening() =>
    _h.complete_action("server listen")
    _client = _TestMuteClient(_h)
    _h.complete_action("client create")

  be dispose() =>
    try (_client as _TestMuteClient).dispose() end
    try (_server as _TestMuteServer).dispose() end
    _tcp_listener.close()

actor \nodoc\ _TestMuteClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.client(
      TCPConnectAuth(_h.env.root),
      "localhost",
      "6666",
      "",
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _h.complete_action("client connected")

  fun ref _on_connection_failure() =>
    _h.fail("client connect failed")

  fun ref _on_received(data: Array[U8] iso) =>
     _tcp_connection.send("it's sad that you won't ever read this")
     _h.complete_action("client sent data")

actor \nodoc\ _TestMuteServer
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
    _h.complete_action("server started")
    _tcp_connection.mute()
    _h.complete_action("server muted")
    _tcp_connection.send("send me some data that i won't ever read")
    _h.complete_action("server asks for data")

  fun ref _on_received(data: Array[U8] iso) =>
    _h.fail("server should not receive data")
    _h.complete(false)

class \nodoc\ iso _TestUnmute is UnitTest
  """
  Test that the `unmute` behavior will allow a connection to start reading
  incoming data again. The test assumes that `mute` works correctly and that
  after muting, `unmute` successfully reset the mute state rather than `mute`
  being broken and never actually muting the connection.

  Test works as follows:

  Once an incoming connection is established, we set mute on it, request
  that data be sent to us and then unmute the connection such that we should
  receive the return data.
  """
  fun name(): String => "TestUnmute"

  fun ref apply(h: TestHelper) =>
    h.expect_action("server listen")
    h.expect_action("client create")
    h.expect_action("server accept")
    h.expect_action("server started")
    h.expect_action("client connected")
    h.expect_action("server muted")
    h.expect_action("server asks for data")
    h.expect_action("server unmuted")
    h.expect_action("client sent data")

    let s = _TestUnmuteListener(h)
    h.dispose_when_done(s)

    h.long_test(5_000_000_000)

actor \nodoc\ _TestUnmuteListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _server: (_TestUnmuteServer | None) = None
  var _client: (_TestUnmuteClient | None) = None

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(_h.env.root),
      "localhost",
      "6767",
      this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestUnmuteServer =>
    _h.complete_action("server accept")
    let s = _TestUnmuteServer(fd, _h)
    _server = s
    s

  fun ref _on_listen_failure() =>
    _h.fail_action("server listen")
    _h.complete(false)

  fun ref _on_listening() =>
    _h.complete_action("server listen")
    _client = _TestUnmuteClient(_h)
    _h.complete_action("client create")

  be dispose() =>
    try (_client as _TestUnmuteClient).dispose() end
    try (_server as _TestUnmuteServer).dispose() end
    _tcp_listener.close()

actor \nodoc\ _TestUnmuteClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.client(
      TCPConnectAuth(_h.env.root),
      "localhost",
      "6767",
      "",
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _h.complete_action("client connected")

  fun ref _on_connection_failure() =>
    _h.fail("client connect failed")

  fun ref _on_received(data: Array[U8] iso) =>
     _tcp_connection.send("i'm happy you will receive this")
     _h.complete_action("client sent data")

actor \nodoc\ _TestUnmuteServer
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
    _h.complete_action("server started")
    _tcp_connection.mute()
    _h.complete_action("server muted")
    _tcp_connection.send("send me some data")
    _h.complete_action("server asks for data")
    _tcp_connection.unmute()
    _h.complete_action("server unmuted")

  fun ref _on_received(data: Array[U8] iso) =>
    _h.complete(true)

class \nodoc\ iso _TestSendToken is UnitTest
  """
  Test that send() returns a SendToken and that _on_sent fires with the
  matching token after data is handed to the OS.
  """
  fun name(): String => "SendToken"

  fun apply(h: TestHelper) =>
    h.expect_action("server listening")
    h.expect_action("client connected")
    h.expect_action("on_sent fired")

    let s = _TestSendTokenListener(h)
    h.dispose_when_done(s)

    h.long_test(5_000_000_000)

actor \nodoc\ _TestSendTokenListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _client: (_TestSendTokenClient | None) = None

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(_h.env.root),
      "localhost",
      "7891",
      this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestSendTokenServer =>
    _TestSendTokenServer(fd, _h)

  fun ref _on_closed() =>
    try (_client as _TestSendTokenClient).dispose() end

  fun ref _on_listening() =>
    _h.complete_action("server listening")
    _client = _TestSendTokenClient(_h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestSendTokenListener")

actor \nodoc\ _TestSendTokenClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper
  var _expected_token: (SendToken | None) = None

  new create(h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.client(
      TCPConnectAuth(_h.env.root),
      "localhost",
      "7891",
      "",
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _h.complete_action("client connected")
    match _tcp_connection.send("hello")
    | let token: SendToken =>
      _expected_token = token
    | let _: SendError =>
      _h.fail("send() returned an error")
      _h.complete(false)
    end

  fun ref _on_sent(token: SendToken) =>
    match _expected_token
    | let expected: SendToken =>
      _h.assert_true(token == expected, "token mismatch")
      _h.complete_action("on_sent fired")
    | None =>
      _h.fail("_on_sent fired but no token was expected")
    end

actor \nodoc\ _TestSendTokenServer
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

class \nodoc\ iso _TestSendAfterClose is UnitTest
  """
  Test that send() returns SendErrorNotConnected after the connection
  has been closed.
  """
  fun name(): String => "SendAfterClose"

  fun apply(h: TestHelper) =>
    h.expect_action("server listening")
    h.expect_action("client connected")
    h.expect_action("send error verified")

    let s = _TestSendAfterCloseListener(h)
    h.dispose_when_done(s)

    h.long_test(5_000_000_000)

actor \nodoc\ _TestSendAfterCloseListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _client: (_TestSendAfterCloseClient | None) = None

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(_h.env.root),
      "localhost",
      "7892",
      this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestSendAfterCloseServer =>
    _TestSendAfterCloseServer(fd, _h)

  fun ref _on_closed() =>
    try (_client as _TestSendAfterCloseClient).dispose() end

  fun ref _on_listening() =>
    _h.complete_action("server listening")
    _client = _TestSendAfterCloseClient(_h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestSendAfterCloseListener")

actor \nodoc\ _TestSendAfterCloseClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.client(
      TCPConnectAuth(_h.env.root),
      "localhost",
      "7892",
      "",
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _h.complete_action("client connected")
    _tcp_connection.close()
    match _tcp_connection.send("should fail")
    | let _: SendToken =>
      _h.fail("send() should have returned an error after close")
      _h.complete(false)
    | let _: SendErrorNotConnected =>
      _h.complete_action("send error verified")
    | let _: SendError =>
      _h.fail("send() returned wrong error type after close")
      _h.complete(false)
    end

actor \nodoc\ _TestSendAfterCloseServer
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
    try _tcp_connection.expect(4)? end

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
    try _tcp_connection.expect(4)? end

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
    try _tcp_connection.expect(2)? end

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
    try _tcp_connection.expect(4)? end
    _tcp_connection.send("Ping")

  fun ref _on_tls_failure() =>
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
    try _tcp_connection.expect(8)? end

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
    try _tcp_connection.expect(4)? end

  fun ref _on_tls_failure() =>
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

class \nodoc\ iso _TestHardCloseWhileConnecting is UnitTest
  """
  Test that hard_close() during the connecting phase fires
  _on_connection_failure() and prevents the connection from going live.
  """
  fun name(): String => "HardCloseWhileConnecting"

  fun apply(h: TestHelper) =>
    h.expect_action("connection failure")

    let listener = _TestHardCloseWhileConnectingListener(h)
    h.dispose_when_done(listener)

    h.long_test(5_000_000_000)

actor \nodoc\ _TestHardCloseWhileConnectingClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.client(
      TCPConnectAuth(_h.env.root),
      "localhost",
      "9735",
      "",
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connecting(count: U32) =>
    _tcp_connection.hard_close()

  fun ref _on_connected() =>
    _h.fail("_on_connected should not fire after hard_close")
    _h.complete(false)

  fun ref _on_connection_failure() =>
    _h.complete_action("connection failure")

actor \nodoc\ _TestHardCloseWhileConnectingListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _client: (_TestHardCloseWhileConnectingClient | None) = None

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(_h.env.root),
      "localhost",
      "9735",
      this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestDoNothingServerActor =>
    _TestDoNothingServerActor(fd, _h)

  fun ref _on_closed() =>
    try (_client as _TestHardCloseWhileConnectingClient).dispose() end

  fun ref _on_listening() =>
    _client = _TestHardCloseWhileConnectingClient(_h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestHardCloseWhileConnectingListener")

class \nodoc\ iso _TestCloseWhileConnecting is UnitTest
  """
  Test that close() during the connecting phase fires
  _on_connection_failure() and prevents the connection from going live.
  """
  fun name(): String => "CloseWhileConnecting"

  fun apply(h: TestHelper) =>
    h.expect_action("connection failure")

    let listener = _TestCloseWhileConnectingListener(h)
    h.dispose_when_done(listener)

    h.long_test(5_000_000_000)

actor \nodoc\ _TestCloseWhileConnectingClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.client(
      TCPConnectAuth(_h.env.root),
      "localhost",
      "9736",
      "",
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connecting(count: U32) =>
    _tcp_connection.close()

  fun ref _on_connected() =>
    _h.fail("_on_connected should not fire after close")
    _h.complete(false)

  fun ref _on_connection_failure() =>
    _h.complete_action("connection failure")

actor \nodoc\ _TestCloseWhileConnectingListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _client: (_TestCloseWhileConnectingClient | None) = None

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(_h.env.root),
      "localhost",
      "9736",
      this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestDoNothingServerActor =>
    _TestDoNothingServerActor(fd, _h)

  fun ref _on_closed() =>
    try (_client as _TestCloseWhileConnectingClient).dispose() end

  fun ref _on_listening() =>
    _client = _TestCloseWhileConnectingClient(_h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestCloseWhileConnectingListener")
