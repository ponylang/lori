use "constrained_types"
use "pony_test"
use "files"
use "ssl/net"
use "time"

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
    test(_TestSendv)
    test(_TestSendvEmpty)
    test(_TestSendvMixedEmpty)
    test(_TestSSLSendv)
    test(_TestIdleTimeout)
    test(_TestIdleTimeoutReset)
    test(_TestIdleTimeoutDisable)
    test(_TestYieldRead)
    test(_TestIP4PingPong)
    test(_TestIP6PingPong)
    test(_TestMaxSpawnRejectsZero)
    test(_TestMaxSpawnAcceptsBoundary)
    test(_TestDefaultMaxSpawn)
    test(_TestReadBufferSizeRejectsZero)
    test(_TestReadBufferSizeAcceptsBoundary)
    test(_TestDefaultReadBufferSize)
    test(_TestReadBufferConstructorSize)
    test(_TestSetReadBufferMinimumSuccess)
    test(_TestSetReadBufferMinimumBelowExpect)
    test(_TestResizeReadBufferSuccess)
    test(_TestResizeReadBufferBelowExpect)
    test(_TestResizeReadBufferBelowMinLowersMin)
    test(_TestExpectAboveBufferMinimum)
    test(_TestExpectAtBufferMinimum)
    test(_TestSocketOptionsConnected)
    test(_TestSocketOptionsNotConnected)
    test(_TestConnectionTimeoutFires)
    test(_TestConnectionTimeoutCancelledOnConnect)
    test(_TestSSLConnectionTimeoutFires)
    test(_TestSSLConnectionTimeoutCancelledOnConnect)
    test(_TestConnectionTimeoutValidationRejectsZero)
    test(_TestConnectionTimeoutValidationAcceptsBoundary)
    test(_TestCloseWhileConnectingWithTimeout)
    test(_TestHardCloseWhileConnectingWithTimeout)

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

  fun ref _on_connection_failure(reason: ConnectionFailureReason) =>
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
    match MakeExpect(4)
    | let e: Expect => _tcp_connection.expect(e)
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
    match MakeExpect(4)
    | let e: Expect => _tcp_connection.expect(e)
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
    match MakeExpect(4)
    | let e: Expect => _tcp_connection.expect(e)
    end

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

  fun ref _on_connection_failure(reason: ConnectionFailureReason) =>
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

  fun ref _on_connection_failure(reason: ConnectionFailureReason) =>
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
    match \exhaustive\ _tcp_connection.send("hello")
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
    match \exhaustive\ _tcp_connection.send("should fail")
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
    match MakeExpect(4)
    | let e: Expect => _tcp_connection.expect(e)
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
    match MakeExpect(4)
    | let e: Expect => _tcp_connection.expect(e)
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
    match MakeExpect(2)
    | let e: Expect => _tcp_connection.expect(e)
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
    match MakeExpect(4)
    | let e: Expect => _tcp_connection.expect(e)
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
    match MakeExpect(8)
    | let e: Expect => _tcp_connection.expect(e)
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
    match MakeExpect(4)
    | let e: Expect => _tcp_connection.expect(e)
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

class \nodoc\ iso _TestHardCloseWhileConnecting is UnitTest
  """
  Test that hard_close() during the connecting phase fires
  _on_connection_failure and prevents the connection from going live.
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

  fun ref _on_connection_failure(reason: ConnectionFailureReason) =>
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
  _on_connection_failure and prevents the connection from going live.
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

  fun ref _on_connection_failure(reason: ConnectionFailureReason) =>
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

class \nodoc\ iso _TestSendv is UnitTest
  """
  Test that send() with multiple buffers delivers them as a single contiguous
  stream and that _on_sent fires with the matching token.
  """
  fun name(): String => "Sendv"

  fun apply(h: TestHelper) =>
    h.expect_action("server listening")
    h.expect_action("client connected")
    h.expect_action("data verified")
    h.expect_action("on_sent fired")

    let s = _TestSendvListener(h)
    h.dispose_when_done(s)

    h.long_test(5_000_000_000)

actor \nodoc\ _TestSendvListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _client: (_TestSendvClient | None) = None

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(_h.env.root),
      "localhost",
      "7893",
      this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestSendvServer =>
    _TestSendvServer(fd, _h)

  fun ref _on_closed() =>
    try (_client as _TestSendvClient).dispose() end

  fun ref _on_listening() =>
    _h.complete_action("server listening")
    _client = _TestSendvClient(_h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestSendvListener")

actor \nodoc\ _TestSendvClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper
  var _expected_token: (SendToken | None) = None

  new create(h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.client(
      TCPConnectAuth(_h.env.root),
      "localhost",
      "7893",
      "",
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _h.complete_action("client connected")
    match \exhaustive\ _tcp_connection.send(
      recover val [as ByteSeq: "Hello"; ", "; "world!"] end)
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

actor \nodoc\ _TestSendvServer
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
    match MakeExpect(13)
    | let e: Expect => _tcp_connection.expect(e)
    end

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_received(data: Array[U8] iso) =>
    _h.assert_eq[String]("Hello, world!", String.from_array(consume data))
    _h.complete_action("data verified")
    _tcp_connection.close()

class \nodoc\ iso _TestSendvEmpty is UnitTest
  """
  Test that send() with an empty ByteSeqIter returns a SendToken and that
  _on_sent fires.
  """
  fun name(): String => "SendvEmpty"

  fun apply(h: TestHelper) =>
    h.expect_action("server listening")
    h.expect_action("client connected")
    h.expect_action("on_sent fired")

    let s = _TestSendvEmptyListener(h)
    h.dispose_when_done(s)

    h.long_test(5_000_000_000)

actor \nodoc\ _TestSendvEmptyListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _client: (_TestSendvEmptyClient | None) = None

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(_h.env.root),
      "localhost",
      "7894",
      this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestDoNothingServerActor =>
    _TestDoNothingServerActor(fd, _h)

  fun ref _on_closed() =>
    try (_client as _TestSendvEmptyClient).dispose() end

  fun ref _on_listening() =>
    _h.complete_action("server listening")
    _client = _TestSendvEmptyClient(_h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestSendvEmptyListener")

actor \nodoc\ _TestSendvEmptyClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper
  var _expected_token: (SendToken | None) = None

  new create(h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.client(
      TCPConnectAuth(_h.env.root),
      "localhost",
      "7894",
      "",
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _h.complete_action("client connected")
    match \exhaustive\ _tcp_connection.send(
      recover val Array[ByteSeq] end)
    | let token: SendToken =>
      _expected_token = token
    | let _: SendError =>
      _h.fail("send() returned an error for empty array")
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

class \nodoc\ iso _TestSendvMixedEmpty is UnitTest
  """
  Test that send() with multiple buffers correctly skips empty buffers.
  Sends ["Hello"; ""; "world"] and verifies the server receives "Helloworld".
  """
  fun name(): String => "SendvMixedEmpty"

  fun apply(h: TestHelper) =>
    h.expect_action("server listening")
    h.expect_action("client connected")
    h.expect_action("data verified")

    let s = _TestSendvMixedEmptyListener(h)
    h.dispose_when_done(s)

    h.long_test(5_000_000_000)

actor \nodoc\ _TestSendvMixedEmptyListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _client: (_TestSendvMixedEmptyClient | None) = None

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(_h.env.root),
      "localhost",
      "7895",
      this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestSendvMixedEmptyServer =>
    _TestSendvMixedEmptyServer(fd, _h)

  fun ref _on_closed() =>
    try (_client as _TestSendvMixedEmptyClient).dispose() end

  fun ref _on_listening() =>
    _h.complete_action("server listening")
    _client = _TestSendvMixedEmptyClient(_h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestSendvMixedEmptyListener")

actor \nodoc\ _TestSendvMixedEmptyClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.client(
      TCPConnectAuth(_h.env.root),
      "localhost",
      "7895",
      "",
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _h.complete_action("client connected")
    _tcp_connection.send(
      recover val [as ByteSeq: "Hello"; ""; "world"] end)

actor \nodoc\ _TestSendvMixedEmptyServer
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
    match MakeExpect(10)
    | let e: Expect => _tcp_connection.expect(e)
    end

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_received(data: Array[U8] iso) =>
    _h.assert_eq[String]("Helloworld", String.from_array(consume data))
    _h.complete_action("data verified")
    _tcp_connection.close()

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
    match MakeExpect(15)
    | let e: Expect => _tcp_connection.expect(e)
    end

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_received(data: Array[U8] iso) =>
    _h.assert_eq[String]("SSL Hello World", String.from_array(consume data))
    _h.complete_action("data verified")
    _tcp_connection.close()

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

  fun ref _on_received(data: Array[U8] iso) =>
    _received_count = _received_count + 1
    if _received_count == 4 then
      _h.complete_action("data received")
    end

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

class \nodoc\ iso _TestYieldRead is UnitTest
  """
  Test that yield_read() exits the read loop without losing data and that
  reading resumes automatically in the next scheduler turn.
  """
  fun name(): String => "YieldRead"

  fun apply(h: TestHelper) =>
    let listener = _TestYieldReadListener(h)
    h.dispose_when_done(listener)

    h.long_test(5_000_000_000)

actor \nodoc\ _TestYieldReadListener is TCPListenerActor
  let _h: TestHelper
  var _tcp_listener: TCPListener = TCPListener.none()
  var _client: (_TestYieldReadClient | None) = None

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(_h.env.root),
      "localhost",
      "7900",
      this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestYieldReadServer =>
    _TestYieldReadServer(fd, _h)

  fun ref _on_closed() =>
    try (_client as _TestYieldReadClient).dispose() end

  fun ref _on_listening() =>
    _client = _TestYieldReadClient(_h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestYieldReadListener")

actor \nodoc\ _TestYieldReadClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.client(
      TCPConnectAuth(_h.env.root),
      "localhost",
      "7900",
      "",
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    var i: USize = 0
    while i < 20 do
      _tcp_connection.send("Ping")
      i = i + 1
    end

actor \nodoc\ _TestYieldReadServer
  is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper
  var _received_count: USize = 0

  new create(fd: U32, h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.server(
      TCPServerAuth(_h.env.root),
      fd,
      this,
      this)
    match MakeExpect(4)
    | let e: Expect => _tcp_connection.expect(e)
    end

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_received(data: Array[U8] iso) =>
    _received_count = _received_count + 1
    _tcp_connection.yield_read()

    if _received_count == 20 then
      _h.complete(true)
      _tcp_connection.close()
    end

class \nodoc\ iso _TestIP4PingPong is UnitTest
  """
  Test that IPv4-only connections work for both listener and client.
  """
  fun name(): String => "IP4PingPong"

  fun apply(h: TestHelper) =>
    let port = "7901"
    let pings_to_send: I32 = 100

    let listener = _TestIP4PongerListener(port, pings_to_send, h)
    h.dispose_when_done(listener)

    h.long_test(5_000_000_000)

actor \nodoc\ _TestIP4Pinger is (TCPConnectionActor & ClientLifecycleEventReceiver)
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
      "127.0.0.1",
      port,
      "",
      this,
      this where ip_version = IP4)
    match MakeExpect(4)
    | let e: Expect => _tcp_connection.expect(e)
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

actor \nodoc\ _TestIP4Ponger is (TCPConnectionActor & ServerLifecycleEventReceiver)
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
    match MakeExpect(4)
    | let e: Expect => _tcp_connection.expect(e)
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

actor \nodoc\ _TestIP4PongerListener is TCPListenerActor
  let _port: String
  var _tcp_listener: TCPListener = TCPListener.none()
  var _pings_to_receive: I32
  let _h: TestHelper
  var _pinger: (_TestIP4Pinger | None) = None

  new create(port: String,
    pings_to_receive: I32,
    h: TestHelper)
  =>
    _port = port
    _pings_to_receive = pings_to_receive
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(_h.env.root),
      "127.0.0.1",
      _port,
      this where ip_version = IP4)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestIP4Ponger =>
    _TestIP4Ponger(fd, _pings_to_receive, _h)

  fun ref _on_closed() =>
    try
      (_pinger as _TestIP4Pinger).dispose()
    end

  fun ref _on_listening() =>
    _pinger = _TestIP4Pinger(_port, _pings_to_receive, _h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestIP4PongerListener")

class \nodoc\ iso _TestIP6PingPong is UnitTest
  """
  Test that IPv6-only connections work for both listener and client.
  """
  fun name(): String => "IP6PingPong"

  fun apply(h: TestHelper) =>
    let port = "7902"
    let pings_to_send: I32 = 100

    let listener = _TestIP6PongerListener(port, pings_to_send, h)
    h.dispose_when_done(listener)

    h.long_test(5_000_000_000)

actor \nodoc\ _TestIP6Pinger is (TCPConnectionActor & ClientLifecycleEventReceiver)
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
      "::1",
      port,
      "",
      this,
      this where ip_version = IP6)
    match MakeExpect(4)
    | let e: Expect => _tcp_connection.expect(e)
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

actor \nodoc\ _TestIP6Ponger is (TCPConnectionActor & ServerLifecycleEventReceiver)
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
    match MakeExpect(4)
    | let e: Expect => _tcp_connection.expect(e)
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

actor \nodoc\ _TestIP6PongerListener is TCPListenerActor
  let _port: String
  var _tcp_listener: TCPListener = TCPListener.none()
  var _pings_to_receive: I32
  let _h: TestHelper
  var _pinger: (_TestIP6Pinger | None) = None

  new create(port: String,
    pings_to_receive: I32,
    h: TestHelper)
  =>
    _port = port
    _pings_to_receive = pings_to_receive
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(_h.env.root),
      "::1",
      _port,
      this where ip_version = IP6)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestIP6Ponger =>
    _TestIP6Ponger(fd, _pings_to_receive, _h)

  fun ref _on_closed() =>
    try
      (_pinger as _TestIP6Pinger).dispose()
    end

  fun ref _on_listening() =>
    _pinger = _TestIP6Pinger(_port, _pings_to_receive, _h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestIP6PongerListener")

class \nodoc\ iso _TestMaxSpawnRejectsZero is UnitTest
  fun name(): String => "MaxSpawnRejectsZero"

  fun apply(h: TestHelper) =>
    match MakeMaxSpawn(0)
    | let _: MaxSpawn =>
      h.fail("MakeMaxSpawn(0) should return ValidationFailure")
    | let _: ValidationFailure =>
      h.assert_true(true)
    end

class \nodoc\ iso _TestMaxSpawnAcceptsBoundary is UnitTest
  fun name(): String => "MaxSpawnAcceptsBoundary"

  fun apply(h: TestHelper) =>
    match MakeMaxSpawn(1)
    | let m: MaxSpawn =>
      h.assert_eq[U32](1, m())
    | let _: ValidationFailure =>
      h.fail("MakeMaxSpawn(1) should succeed")
    end

    match MakeMaxSpawn(U32.max_value())
    | let m: MaxSpawn =>
      h.assert_eq[U32](U32.max_value(), m())
    | let _: ValidationFailure =>
      h.fail("MakeMaxSpawn(U32.max_value()) should succeed")
    end

class \nodoc\ iso _TestDefaultMaxSpawn is UnitTest
  fun name(): String => "DefaultMaxSpawn"

  fun apply(h: TestHelper) =>
    h.assert_eq[U32](100_000, DefaultMaxSpawn()())

class \nodoc\ iso _TestReadBufferSizeRejectsZero is UnitTest
  fun name(): String => "ReadBufferSizeRejectsZero"

  fun apply(h: TestHelper) =>
    match MakeReadBufferSize(0)
    | let _: ReadBufferSize =>
      h.fail("MakeReadBufferSize(0) should return ValidationFailure")
    | let _: ValidationFailure =>
      h.assert_true(true)
    end

class \nodoc\ iso _TestReadBufferSizeAcceptsBoundary is UnitTest
  fun name(): String => "ReadBufferSizeAcceptsBoundary"

  fun apply(h: TestHelper) =>
    match MakeReadBufferSize(1)
    | let r: ReadBufferSize =>
      h.assert_eq[USize](1, r())
    | let _: ValidationFailure =>
      h.fail("MakeReadBufferSize(1) should succeed")
    end

    match MakeReadBufferSize(USize.max_value())
    | let r: ReadBufferSize =>
      h.assert_eq[USize](USize.max_value(), r())
    | let _: ValidationFailure =>
      h.fail("MakeReadBufferSize(USize.max_value()) should succeed")
    end

class \nodoc\ iso _TestDefaultReadBufferSize is UnitTest
  fun name(): String => "DefaultReadBufferSize"

  fun apply(h: TestHelper) =>
    h.assert_eq[USize](16384, DefaultReadBufferSize()())

class \nodoc\ iso _TestReadBufferConstructorSize is UnitTest
  """
  Test that the constructor parameter sets the initial buffer size and minimum.
  The server verifies buffer behavior by resizing and checking invariants.
  """
  fun name(): String => "ReadBufferConstructorSize"

  fun apply(h: TestHelper) =>
    let listener = _TestReadBufferConstructorSizeListener(h)
    h.dispose_when_done(listener)
    h.long_test(5_000_000_000)

actor \nodoc\ _TestReadBufferConstructorSizeListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(h.env.root), "127.0.0.1", "7700", this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestReadBufferConstructorSizeServer =>
    _TestReadBufferConstructorSizeServer(fd, _h)

  fun ref _on_listening() =>
    // Connect a client just to trigger _on_accept
    _TestReadBufferTriggerClient(TCPConnectAuth(_h.env.root),
      "127.0.0.1", "7700")

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open listener")

actor \nodoc\ _TestReadBufferConstructorSizeServer is
  (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(fd: U32, h: TestHelper) =>
    _h = h
    // Use a custom buffer size of 512
    match MakeReadBufferSize(512)
    | let rbs: ReadBufferSize =>
      _tcp_connection = TCPConnection.server(
        TCPServerAuth(h.env.root), fd, this, this
        where read_buffer_size = rbs)
    | let _: ValidationFailure =>
      _h.fail("MakeReadBufferSize(512) should succeed")
    end

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_started() =>
    // set_read_buffer_minimum to 256 should succeed (lowering the minimum)
    match MakeReadBufferSize(256)
    | let rbs: ReadBufferSize =>
      match _tcp_connection.set_read_buffer_minimum(rbs)
      | ReadBufferResized => None
      | ReadBufferResizeBelowExpect =>
        _h.fail("set_read_buffer_minimum(256) should succeed")
      end

      // resize_read_buffer to 256 should succeed since minimum is now 256
      match _tcp_connection.resize_read_buffer(rbs)
      | ReadBufferResized => None
      | let _: ReadBufferResizeBelowExpect =>
        _h.fail("resize_read_buffer(256) should succeed")
      | let _: ReadBufferResizeBelowUsed =>
        _h.fail("resize_read_buffer(256) should succeed")
      end
    | let _: ValidationFailure =>
      _h.fail("MakeReadBufferSize(256) should succeed")
    end

    _h.complete(true)
    _tcp_connection.close()

class \nodoc\ iso _TestSetReadBufferMinimumSuccess is UnitTest
  """
  Test that set_read_buffer_minimum() succeeds and grows the buffer when
  the new minimum exceeds the current allocation.
  """
  fun name(): String => "SetReadBufferMinimumSuccess"

  fun apply(h: TestHelper) =>
    let listener = _TestSetReadBufferMinSuccessListener(h)
    h.dispose_when_done(listener)
    h.long_test(5_000_000_000)

actor \nodoc\ _TestSetReadBufferMinSuccessListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(h.env.root), "127.0.0.1", "7701", this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestSetReadBufferMinSuccessServer =>
    _TestSetReadBufferMinSuccessServer(fd, _h)

  fun ref _on_listening() =>
    _TestReadBufferTriggerClient(TCPConnectAuth(_h.env.root),
      "127.0.0.1", "7701")

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open listener")

actor \nodoc\ _TestSetReadBufferMinSuccessServer is
  (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(fd: U32, h: TestHelper) =>
    _h = h
    match MakeReadBufferSize(256)
    | let rbs: ReadBufferSize =>
      _tcp_connection = TCPConnection.server(
        TCPServerAuth(h.env.root), fd, this, this
        where read_buffer_size = rbs)
    | let _: ValidationFailure =>
      _h.fail("MakeReadBufferSize(256) should succeed")
    end

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_started() =>
    // Setting minimum to 512 should succeed and grow the buffer
    match MakeReadBufferSize(512)
    | let rbs: ReadBufferSize =>
      match _tcp_connection.set_read_buffer_minimum(rbs)
      | ReadBufferResized => None
      | ReadBufferResizeBelowExpect =>
        _h.fail("set_read_buffer_minimum(512) should succeed")
      end
    | let _: ValidationFailure =>
      _h.fail("MakeReadBufferSize(512) should succeed")
    end

    // Setting minimum back to 128 should succeed (lowering is always ok)
    match MakeReadBufferSize(128)
    | let rbs: ReadBufferSize =>
      match _tcp_connection.set_read_buffer_minimum(rbs)
      | ReadBufferResized => None
      | ReadBufferResizeBelowExpect =>
        _h.fail("set_read_buffer_minimum(128) should succeed")
      end
    | let _: ValidationFailure =>
      _h.fail("MakeReadBufferSize(128) should succeed")
    end

    _h.complete(true)
    _tcp_connection.close()

class \nodoc\ iso _TestSetReadBufferMinimumBelowExpect is UnitTest
  """
  Test that set_read_buffer_minimum() fails when the new minimum is below
  the current expect value.
  """
  fun name(): String => "SetReadBufferMinimumBelowExpect"

  fun apply(h: TestHelper) =>
    let listener = _TestSetReadBufferMinBelowExpectListener(h)
    h.dispose_when_done(listener)
    h.long_test(5_000_000_000)

actor \nodoc\ _TestSetReadBufferMinBelowExpectListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(h.env.root), "127.0.0.1", "7702", this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestSetReadBufferMinBelowExpectServer =>
    _TestSetReadBufferMinBelowExpectServer(fd, _h)

  fun ref _on_listening() =>
    _TestReadBufferTriggerClient(TCPConnectAuth(_h.env.root),
      "127.0.0.1", "7702")

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open listener")

actor \nodoc\ _TestSetReadBufferMinBelowExpectServer is
  (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(fd: U32, h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.server(
      TCPServerAuth(h.env.root), fd, this, this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_started() =>
    // Set expect to 100
    match MakeExpect(100)
    | let e: Expect => _tcp_connection.expect(e)
    end

    // Setting minimum below expect should fail
    match MakeReadBufferSize(50)
    | let rbs: ReadBufferSize =>
      match _tcp_connection.set_read_buffer_minimum(rbs)
      | ReadBufferResized =>
        _h.fail(
          "set_read_buffer_minimum(50) should fail when expect is 100")
      | ReadBufferResizeBelowExpect => None
      end
    | let _: ValidationFailure =>
      _h.fail("MakeReadBufferSize(50) should succeed")
    end

    // Setting minimum at expect should succeed
    match MakeReadBufferSize(100)
    | let rbs: ReadBufferSize =>
      match _tcp_connection.set_read_buffer_minimum(rbs)
      | ReadBufferResized => None
      | ReadBufferResizeBelowExpect =>
        _h.fail(
          "set_read_buffer_minimum(100) should succeed when expect is 100")
      end
    | let _: ValidationFailure =>
      _h.fail("MakeReadBufferSize(100) should succeed")
    end

    _h.complete(true)
    _tcp_connection.close()

class \nodoc\ iso _TestResizeReadBufferSuccess is UnitTest
  """
  Test that resize_read_buffer() succeeds for valid sizes.
  """
  fun name(): String => "ResizeReadBufferSuccess"

  fun apply(h: TestHelper) =>
    let listener = _TestResizeReadBufferSuccessListener(h)
    h.dispose_when_done(listener)
    h.long_test(5_000_000_000)

actor \nodoc\ _TestResizeReadBufferSuccessListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(h.env.root), "127.0.0.1", "7703", this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestResizeReadBufferSuccessServer =>
    _TestResizeReadBufferSuccessServer(fd, _h)

  fun ref _on_listening() =>
    _TestReadBufferTriggerClient(TCPConnectAuth(_h.env.root),
      "127.0.0.1", "7703")

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open listener")

actor \nodoc\ _TestResizeReadBufferSuccessServer is
  (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(fd: U32, h: TestHelper) =>
    _h = h
    match MakeReadBufferSize(1024)
    | let rbs: ReadBufferSize =>
      _tcp_connection = TCPConnection.server(
        TCPServerAuth(h.env.root), fd, this, this
        where read_buffer_size = rbs)
    | let _: ValidationFailure =>
      _h.fail("MakeReadBufferSize(1024) should succeed")
    end

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_started() =>
    // Resize to larger
    match MakeReadBufferSize(4096)
    | let rbs: ReadBufferSize =>
      match _tcp_connection.resize_read_buffer(rbs)
      | ReadBufferResized => None
      | let _: ReadBufferResizeBelowExpect =>
        _h.fail("resize_read_buffer(4096) should succeed")
      | let _: ReadBufferResizeBelowUsed =>
        _h.fail("resize_read_buffer(4096) should succeed")
      end
    | let _: ValidationFailure =>
      _h.fail("MakeReadBufferSize(4096) should succeed")
    end

    // Resize to smaller (also lowers minimum)
    match MakeReadBufferSize(512)
    | let rbs: ReadBufferSize =>
      match _tcp_connection.resize_read_buffer(rbs)
      | ReadBufferResized => None
      | let _: ReadBufferResizeBelowExpect =>
        _h.fail("resize_read_buffer(512) should succeed")
      | let _: ReadBufferResizeBelowUsed =>
        _h.fail("resize_read_buffer(512) should succeed")
      end
    | let _: ValidationFailure =>
      _h.fail("MakeReadBufferSize(512) should succeed")
    end

    _h.complete(true)
    _tcp_connection.close()

class \nodoc\ iso _TestResizeReadBufferBelowExpect is UnitTest
  """
  Test that resize_read_buffer() fails when the size is below the current
  expect value.
  """
  fun name(): String => "ResizeReadBufferBelowExpect"

  fun apply(h: TestHelper) =>
    let listener = _TestResizeReadBufferBelowExpectListener(h)
    h.dispose_when_done(listener)
    h.long_test(5_000_000_000)

actor \nodoc\ _TestResizeReadBufferBelowExpectListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(h.env.root), "127.0.0.1", "7704", this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestResizeReadBufferBelowExpectServer =>
    _TestResizeReadBufferBelowExpectServer(fd, _h)

  fun ref _on_listening() =>
    _TestReadBufferTriggerClient(TCPConnectAuth(_h.env.root),
      "127.0.0.1", "7704")

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open listener")

actor \nodoc\ _TestResizeReadBufferBelowExpectServer is
  (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(fd: U32, h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.server(
      TCPServerAuth(h.env.root), fd, this, this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_started() =>
    // Set expect to 200
    match MakeExpect(200)
    | let e: Expect => _tcp_connection.expect(e)
    end

    // Resize below expect should fail
    match MakeReadBufferSize(100)
    | let rbs: ReadBufferSize =>
      match _tcp_connection.resize_read_buffer(rbs)
      | ReadBufferResized =>
        _h.fail("resize_read_buffer(100) should fail when expect is 200")
      | let _: ReadBufferResizeBelowExpect => None
      | let _: ReadBufferResizeBelowUsed =>
        _h.fail(
          "should be ReadBufferResizeBelowExpect, not ReadBufferResizeBelowUsed"
          )
      end
    | let _: ValidationFailure =>
      _h.fail("MakeReadBufferSize(100) should succeed")
    end

    _h.complete(true)
    _tcp_connection.close()

class \nodoc\ iso _TestResizeReadBufferBelowMinLowersMin is UnitTest
  """
  Test that resize_read_buffer() below the current minimum lowers the minimum.
  Verified by subsequently setting expect to the old minimum (which would fail
  if the minimum hadn't been lowered).
  """
  fun name(): String => "ResizeReadBufferBelowMinLowersMin"

  fun apply(h: TestHelper) =>
    let listener = _TestResizeReadBufferBelowMinListener(h)
    h.dispose_when_done(listener)
    h.long_test(5_000_000_000)

actor \nodoc\ _TestResizeReadBufferBelowMinListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(h.env.root), "127.0.0.1", "7705", this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestResizeReadBufferBelowMinServer =>
    _TestResizeReadBufferBelowMinServer(fd, _h)

  fun ref _on_listening() =>
    _TestReadBufferTriggerClient(TCPConnectAuth(_h.env.root),
      "127.0.0.1", "7705")

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open listener")

actor \nodoc\ _TestResizeReadBufferBelowMinServer is
  (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(fd: U32, h: TestHelper) =>
    _h = h
    // Start with buffer size 1024 (min is also 1024)
    match MakeReadBufferSize(1024)
    | let rbs: ReadBufferSize =>
      _tcp_connection = TCPConnection.server(
        TCPServerAuth(h.env.root), fd, this, this
        where read_buffer_size = rbs)
    | let _: ValidationFailure =>
      _h.fail("MakeReadBufferSize(1024) should succeed")
    end

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_started() =>
    // Resize to 256 — this should lower the minimum from 1024 to 256
    match MakeReadBufferSize(256)
    | let rbs: ReadBufferSize =>
      match _tcp_connection.resize_read_buffer(rbs)
      | ReadBufferResized => None
      | let _: ReadBufferResizeBelowExpect =>
        _h.fail("resize_read_buffer(256) should succeed")
      | let _: ReadBufferResizeBelowUsed =>
        _h.fail("resize_read_buffer(256) should succeed")
      end
    | let _: ValidationFailure =>
      _h.fail("MakeReadBufferSize(256) should succeed")
    end

    // Now expect(512) should fail because minimum was lowered to 256
    match MakeExpect(512)
    | let e: Expect =>
      match _tcp_connection.expect(e)
      | ExpectSet =>
        _h.fail("expect(512) should fail when minimum is 256")
      | ExpectAboveBufferMinimum => None
      end
    end

    // expect(256) should succeed (at the new minimum)
    match MakeExpect(256)
    | let e: Expect =>
      match _tcp_connection.expect(e)
      | ExpectSet => None
      | ExpectAboveBufferMinimum =>
        _h.fail("expect(256) should succeed when minimum is 256")
      end
    end

    _h.complete(true)
    _tcp_connection.close()

class \nodoc\ iso _TestExpectAboveBufferMinimum is UnitTest
  """
  Test that expect() fails when the requested value exceeds the buffer minimum.
  """
  fun name(): String => "ExpectAboveBufferMinimum"

  fun apply(h: TestHelper) =>
    let listener = _TestExpectAboveBufferMinListener(h)
    h.dispose_when_done(listener)
    h.long_test(5_000_000_000)

actor \nodoc\ _TestExpectAboveBufferMinListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(h.env.root), "127.0.0.1", "7706", this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestExpectAboveBufferMinServer =>
    _TestExpectAboveBufferMinServer(fd, _h)

  fun ref _on_listening() =>
    _TestReadBufferTriggerClient(TCPConnectAuth(_h.env.root),
      "127.0.0.1", "7706")

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open listener")

actor \nodoc\ _TestExpectAboveBufferMinServer is
  (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(fd: U32, h: TestHelper) =>
    _h = h
    // Start with buffer size 128 (min is also 128)
    match MakeReadBufferSize(128)
    | let rbs: ReadBufferSize =>
      _tcp_connection = TCPConnection.server(
        TCPServerAuth(h.env.root), fd, this, this
        where read_buffer_size = rbs)
    | let _: ValidationFailure =>
      _h.fail("MakeReadBufferSize(128) should succeed")
    end

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_started() =>
    // expect(256) should fail because minimum is 128
    match MakeExpect(256)
    | let e: Expect =>
      match _tcp_connection.expect(e)
      | ExpectSet =>
        _h.fail("expect(256) should fail when minimum is 128")
      | ExpectAboveBufferMinimum => None
      end
    end

    _h.complete(true)
    _tcp_connection.close()

class \nodoc\ iso _TestExpectAtBufferMinimum is UnitTest
  """
  Test that expect() succeeds when the requested value equals the buffer
  minimum.
  """
  fun name(): String => "ExpectAtBufferMinimum"

  fun apply(h: TestHelper) =>
    let listener = _TestExpectAtBufferMinListener(h)
    h.dispose_when_done(listener)
    h.long_test(5_000_000_000)

actor \nodoc\ _TestExpectAtBufferMinListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(h.env.root), "127.0.0.1", "7707", this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestExpectAtBufferMinServer =>
    _TestExpectAtBufferMinServer(fd, _h)

  fun ref _on_listening() =>
    _TestReadBufferTriggerClient(TCPConnectAuth(_h.env.root),
      "127.0.0.1", "7707")

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open listener")

actor \nodoc\ _TestExpectAtBufferMinServer is
  (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(fd: U32, h: TestHelper) =>
    _h = h
    match MakeReadBufferSize(256)
    | let rbs: ReadBufferSize =>
      _tcp_connection = TCPConnection.server(
        TCPServerAuth(h.env.root), fd, this, this
        where read_buffer_size = rbs)
    | let _: ValidationFailure =>
      _h.fail("MakeReadBufferSize(256) should succeed")
    end

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_started() =>
    // expect(256) should succeed (equals minimum)
    match MakeExpect(256)
    | let e: Expect =>
      match _tcp_connection.expect(e)
      | ExpectSet => None
      | ExpectAboveBufferMinimum =>
        _h.fail("expect(256) should succeed when minimum is 256")
      end
    end

    _h.complete(true)
    _tcp_connection.close()

actor \nodoc\ _TestReadBufferTriggerClient is
  (TCPConnectionActor & ClientLifecycleEventReceiver)
  """
  Minimal client that connects to trigger a server-side _on_accept, then
  closes. Used by read buffer tests that only need a server connection.
  """
  var _tcp_connection: TCPConnection = TCPConnection.none()

  new create(auth: TCPConnectAuth, host: String, port: String) =>
    _tcp_connection = TCPConnection.client(auth, host, port, "", this, this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _tcp_connection.close()

class \nodoc\ iso _TestSocketOptionsConnected is UnitTest
  """
  Test that socket option methods succeed on a connected socket, including
  convenience methods (set_nodelay, set_so_rcvbuf, etc.) and general-purpose
  getsockopt/setsockopt/getsockopt_u32/setsockopt_u32.
  """
  fun name(): String => "SocketOptionsConnected"

  fun apply(h: TestHelper) =>
    let listener = _TestSocketOptionsListener(h)
    h.dispose_when_done(listener)
    h.long_test(5_000_000_000)

actor \nodoc\ _TestSocketOptionsListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(h.env.root), "127.0.0.1", "7708", this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestSocketOptionsServer =>
    _TestSocketOptionsServer(fd, _h)

  fun ref _on_listening() =>
    _TestReadBufferTriggerClient(TCPConnectAuth(_h.env.root),
      "127.0.0.1", "7708")

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open listener")

actor \nodoc\ _TestSocketOptionsServer is
  (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(fd: U32, h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.server(
      TCPServerAuth(h.env.root), fd, this, this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_started() =>
    // set_nodelay: enable and disable should both succeed
    _h.assert_eq[U32](0, _tcp_connection.set_nodelay(true),
      "set_nodelay(true) should succeed")
    _h.assert_eq[U32](0, _tcp_connection.set_nodelay(false),
      "set_nodelay(false) should succeed")

    // set_so_rcvbuf: set then get. OS may round up, so check >= requested.
    let rcvbuf_result = _tcp_connection.set_so_rcvbuf(8192)
    _h.assert_eq[U32](0, rcvbuf_result, "set_so_rcvbuf should succeed")
    (let rcv_errno: U32, let rcv_size: U32) =
      _tcp_connection.get_so_rcvbuf()
    _h.assert_eq[U32](0, rcv_errno, "get_so_rcvbuf errno should be 0")
    _h.assert_true(rcv_size >= 8192,
      "get_so_rcvbuf should return >= 8192, got " + rcv_size.string())

    // set_so_sndbuf: set then get. OS may round up, so check >= requested.
    let sndbuf_result = _tcp_connection.set_so_sndbuf(8192)
    _h.assert_eq[U32](0, sndbuf_result, "set_so_sndbuf should succeed")
    (let snd_errno: U32, let snd_size: U32) =
      _tcp_connection.get_so_sndbuf()
    _h.assert_eq[U32](0, snd_errno, "get_so_sndbuf errno should be 0")
    _h.assert_true(snd_size >= 8192,
      "get_so_sndbuf should return >= 8192, got " + snd_size.string())

    // setsockopt_u32/getsockopt_u32: set SO_RCVBUF via general method,
    // read back via general method.
    let gen_set_result = _tcp_connection.setsockopt_u32(
      OSSockOpt.sol_socket(), OSSockOpt.so_rcvbuf(), 16384)
    _h.assert_eq[U32](0, gen_set_result,
      "setsockopt_u32 SO_RCVBUF should succeed")
    (let gen_get_errno: U32, let gen_get_size: U32) =
      _tcp_connection.getsockopt_u32(
        OSSockOpt.sol_socket(), OSSockOpt.so_rcvbuf())
    _h.assert_eq[U32](0, gen_get_errno,
      "getsockopt_u32 SO_RCVBUF errno should be 0")
    _h.assert_true(gen_get_size >= 16384,
      "getsockopt_u32 SO_RCVBUF should return >= 16384, got "
        + gen_get_size.string())

    // setsockopt/getsockopt: set SO_SNDBUF via raw bytes, read back via
    // raw bytes.
    let raw_set_result = _tcp_connection.setsockopt(
      OSSockOpt.sol_socket(), OSSockOpt.so_sndbuf(),
      Array[U8](4).>push_u32(16384))
    _h.assert_eq[U32](0, raw_set_result,
      "setsockopt SO_SNDBUF should succeed")
    (let raw_get_errno: U32, let raw_get_bytes: Array[U8] iso) =
      _tcp_connection.getsockopt(
        OSSockOpt.sol_socket(), OSSockOpt.so_sndbuf())
    _h.assert_eq[U32](0, raw_get_errno,
      "getsockopt SO_SNDBUF errno should be 0")
    try
      let raw_get_size = (consume raw_get_bytes).read_u32(0)?
      _h.assert_true(raw_get_size >= 16384,
        "getsockopt SO_SNDBUF should return >= 16384, got "
          + raw_get_size.string())
    else
      _h.fail("getsockopt SO_SNDBUF returned too few bytes")
    end

    _h.complete(true)
    _tcp_connection.close()

class \nodoc\ iso _TestSocketOptionsNotConnected is UnitTest
  """
  Test that socket option methods return non-zero errno on a connection
  that is not open, including both convenience methods and general-purpose
  getsockopt/setsockopt.
  """
  fun name(): String => "SocketOptionsNotConnected"

  fun apply(h: TestHelper) =>
    let conn = TCPConnection.none()

    h.assert_true(conn.set_nodelay(true) != 0,
      "set_nodelay on none should return non-zero")
    h.assert_true(conn.set_so_rcvbuf(8192) != 0,
      "set_so_rcvbuf on none should return non-zero")
    h.assert_true(conn.set_so_sndbuf(8192) != 0,
      "set_so_sndbuf on none should return non-zero")

    (let rcv_errno: U32, _) = conn.get_so_rcvbuf()
    h.assert_true(rcv_errno != 0,
      "get_so_rcvbuf on none should return non-zero errno")
    (let snd_errno: U32, _) = conn.get_so_sndbuf()
    h.assert_true(snd_errno != 0,
      "get_so_sndbuf on none should return non-zero errno")

    // General-purpose methods
    h.assert_true(
      conn.setsockopt_u32(
        OSSockOpt.sol_socket(), OSSockOpt.so_rcvbuf(), 8192) != 0,
      "setsockopt_u32 on none should return non-zero")
    h.assert_true(
      conn.setsockopt(
        OSSockOpt.sol_socket(), OSSockOpt.so_rcvbuf(),
        Array[U8](4).>push_u32(8192)) != 0,
      "setsockopt on none should return non-zero")

    (let gen_u32_errno: U32, _) =
      conn.getsockopt_u32(OSSockOpt.sol_socket(), OSSockOpt.so_rcvbuf())
    h.assert_true(gen_u32_errno != 0,
      "getsockopt_u32 on none should return non-zero errno")
    (let gen_errno: U32, _) =
      conn.getsockopt(OSSockOpt.sol_socket(), OSSockOpt.so_rcvbuf())
    h.assert_true(gen_errno != 0,
      "getsockopt on none should return non-zero errno")

class \nodoc\ iso _TestConnectionTimeoutFires is UnitTest
  """
  Test that the connection timeout fires when connecting to a non-routable
  address. Connects to 192.0.2.1 (RFC 5737 TEST-NET-1) with a 2-second
  timeout.
  """
  fun name(): String => "ConnectionTimeoutFires"

  fun apply(h: TestHelper) =>
    let client = _TestConnectionTimeoutFiresClient(h)
    h.dispose_when_done(client)

    h.long_test(15_000_000_000)

actor \nodoc\ _TestConnectionTimeoutFiresClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h
    match MakeConnectionTimeout(2_000)
    | let ct: ConnectionTimeout =>
      _tcp_connection = TCPConnection.client(
        TCPConnectAuth(_h.env.root),
        "192.0.2.1",
        "9737",
        "",
        this,
        this
        where connection_timeout = ct)
    | let _: ValidationFailure =>
      _h.fail("MakeConnectionTimeout(2_000) should succeed")
    end

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _h.fail("_on_connected for a connection that should have timed out")
    _h.complete(false)

  fun ref _on_connection_failure(reason: ConnectionFailureReason) =>
    match reason
    | ConnectionFailedTimeout =>
      _h.complete(true)
    else
      _h.fail("Expected ConnectionFailedTimeout, got a different reason")
      _h.complete(false)
    end

class \nodoc\ iso _TestConnectionTimeoutCancelledOnConnect is UnitTest
  """
  Test that the connect timer is cancelled when a connection succeeds.
  Starts a local listener, connects a client with a long timeout, and
  verifies _on_connected fires normally.
  """
  fun name(): String => "ConnectionTimeoutCancelledOnConnect"

  fun apply(h: TestHelper) =>
    let listener = _TestConnectionTimeoutCancelListener(h)
    h.dispose_when_done(listener)

    h.long_test(15_000_000_000)

actor \nodoc\ _TestConnectionTimeoutCancelListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _client: (_TestConnectionTimeoutCancelClient | None) = None

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(_h.env.root),
      "localhost",
      "9738",
      this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestConnectionTimeoutCancelServer =>
    _TestConnectionTimeoutCancelServer(fd, _h)

  fun ref _on_closed() =>
    try (_client as _TestConnectionTimeoutCancelClient).dispose() end

  fun ref _on_listening() =>
    _client = _TestConnectionTimeoutCancelClient(_h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestConnectionTimeoutCancelListener")

actor \nodoc\ _TestConnectionTimeoutCancelClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h
    match MakeConnectionTimeout(30_000)
    | let ct: ConnectionTimeout =>
      _tcp_connection = TCPConnection.client(
        TCPConnectAuth(_h.env.root),
        "localhost",
        "9738",
        "",
        this,
        this
        where connection_timeout = ct)
    | let _: ValidationFailure =>
      _h.fail("MakeConnectionTimeout(30_000) should succeed")
    end

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _h.complete(true)

  fun ref _on_connection_failure(reason: ConnectionFailureReason) =>
    _h.fail("Connection should have succeeded, got failure")
    _h.complete(false)

actor \nodoc\ _TestConnectionTimeoutCancelServer
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

class \nodoc\ iso _TestConnectionTimeoutValidationRejectsZero is UnitTest
  fun name(): String => "ConnectionTimeoutValidationRejectsZero"

  fun apply(h: TestHelper) =>
    match MakeConnectionTimeout(0)
    | let _: ConnectionTimeout =>
      h.fail("MakeConnectionTimeout(0) should return ValidationFailure")
    | let _: ValidationFailure =>
      h.assert_true(true)
    end

class \nodoc\ iso _TestConnectionTimeoutValidationAcceptsBoundary is UnitTest
  fun name(): String => "ConnectionTimeoutValidationAcceptsBoundary"

  fun apply(h: TestHelper) =>
    match MakeConnectionTimeout(1)
    | let ct: ConnectionTimeout =>
      h.assert_eq[U64](1, ct())
    | let _: ValidationFailure =>
      h.fail("MakeConnectionTimeout(1) should succeed")
    end

    match MakeConnectionTimeout(U64.max_value() / 1_000_000)
    | let ct: ConnectionTimeout =>
      h.assert_eq[U64](U64.max_value() / 1_000_000, ct())
    | let _: ValidationFailure =>
      h.fail("MakeConnectionTimeout(U64.max_value() / 1_000_000) should succeed")
    end

    match MakeConnectionTimeout((U64.max_value() / 1_000_000) + 1)
    | let _: ConnectionTimeout =>
      h.fail(
        "MakeConnectionTimeout(max + 1) should return ValidationFailure")
    | let _: ValidationFailure =>
      h.assert_true(true)
    end

class \nodoc\ iso _TestSSLConnectionTimeoutFires is UnitTest
  """
  Test that the connection timeout fires during SSL handshake. Connects an
  ssl_client to a plain TCP server — TCP connects but the SSL handshake
  stalls because the server doesn't speak TLS. Exercises the
  _hard_close_connected() timeout path (distinct from the plaintext
  _hard_close_connecting() path).
  """
  fun name(): String => "SSLConnectionTimeoutFires"

  fun apply(h: TestHelper) ? =>
    let sslctx =
      recover
        SSLContext
          .> set_authority(
            FilePath(FileAuth(h.env.root), "assets/cert.pem"))?
          .> set_client_verify(false)
          .> set_server_verify(false)
      end

    let listener = _TestSSLConnectionTimeoutFiresListener(
      consume sslctx, h)
    h.dispose_when_done(listener)

    h.long_test(15_000_000_000)

actor \nodoc\ _TestSSLConnectionTimeoutFiresListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _sslctx: SSLContext val
  let _h: TestHelper
  var _client: (_TestSSLConnectionTimeoutFiresClient | None) = None

  new create(sslctx: SSLContext val, h: TestHelper) =>
    _sslctx = sslctx
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(_h.env.root),
      "localhost",
      "9739",
      this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestSSLConnectionTimeoutFiresServer =>
    _TestSSLConnectionTimeoutFiresServer(fd, _h)

  fun ref _on_closed() =>
    try (_client as _TestSSLConnectionTimeoutFiresClient).dispose() end

  fun ref _on_listening() =>
    _client = _TestSSLConnectionTimeoutFiresClient(_sslctx, _h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestSSLConnectionTimeoutFiresListener")

actor \nodoc\ _TestSSLConnectionTimeoutFiresClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(sslctx: SSLContext val, h: TestHelper) =>
    _h = h
    match MakeConnectionTimeout(2_000)
    | let ct: ConnectionTimeout =>
      _tcp_connection = TCPConnection.ssl_client(
        TCPConnectAuth(_h.env.root),
        sslctx,
        "localhost",
        "9739",
        "",
        this,
        this
        where connection_timeout = ct)
    | let _: ValidationFailure =>
      _h.fail("MakeConnectionTimeout(2_000) should succeed")
    end

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _h.fail("_on_connected for SSL connection that should have timed out")
    _h.complete(false)

  fun ref _on_connection_failure(reason: ConnectionFailureReason) =>
    match reason
    | ConnectionFailedTimeout =>
      _h.complete(true)
    else
      _h.fail("Expected ConnectionFailedTimeout, got a different reason")
      _h.complete(false)
    end

actor \nodoc\ _TestSSLConnectionTimeoutFiresServer
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

class \nodoc\ iso _TestSSLConnectionTimeoutCancelledOnConnect is UnitTest
  """
  Test that the connect timer is cancelled when an SSL handshake completes.
  Connects an ssl_client to a proper SSL server with a long timeout and
  verifies _on_connected fires. Exercises the _cancel_connect_timer() call
  in _ssl_poll() at the SSLReady branch.
  """
  fun name(): String => "SSLConnectionTimeoutCancelledOnConnect"

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

    let listener = _TestSSLConnectionTimeoutCancelListener(
      consume sslctx, h)
    h.dispose_when_done(listener)

    h.long_test(15_000_000_000)

actor \nodoc\ _TestSSLConnectionTimeoutCancelListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _sslctx: SSLContext val
  let _h: TestHelper
  var _client: (_TestSSLConnectionTimeoutCancelClient | None) = None

  new create(sslctx: SSLContext val, h: TestHelper) =>
    _sslctx = sslctx
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(_h.env.root),
      "localhost",
      "9740",
      this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestSSLConnectionTimeoutCancelSSLServer =>
    _TestSSLConnectionTimeoutCancelSSLServer(_sslctx, fd, _h)

  fun ref _on_closed() =>
    try (_client as _TestSSLConnectionTimeoutCancelClient).dispose() end

  fun ref _on_listening() =>
    _client = _TestSSLConnectionTimeoutCancelClient(_sslctx, _h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestSSLConnectionTimeoutCancelListener")

actor \nodoc\ _TestSSLConnectionTimeoutCancelClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(sslctx: SSLContext val, h: TestHelper) =>
    _h = h
    match MakeConnectionTimeout(30_000)
    | let ct: ConnectionTimeout =>
      _tcp_connection = TCPConnection.ssl_client(
        TCPConnectAuth(_h.env.root),
        sslctx,
        "localhost",
        "9740",
        "",
        this,
        this
        where connection_timeout = ct)
    | let _: ValidationFailure =>
      _h.fail("MakeConnectionTimeout(30_000) should succeed")
    end

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _h.complete(true)

  fun ref _on_connection_failure(reason: ConnectionFailureReason) =>
    _h.fail("SSL connection should have succeeded, got failure")
    _h.complete(false)

actor \nodoc\ _TestSSLConnectionTimeoutCancelSSLServer
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

class \nodoc\ iso _TestCloseWhileConnectingWithTimeout is UnitTest
  """
  Test that close() during the connecting phase with a connect timeout armed
  cancels the timer and reports ConnectionFailedTCP, not ConnectionFailedTimeout.
  """
  fun name(): String => "CloseWhileConnectingWithTimeout"

  fun apply(h: TestHelper) =>
    let listener = _TestCloseWhileConnectingWithTimeoutListener(h)
    h.dispose_when_done(listener)

    h.long_test(5_000_000_000)

actor \nodoc\ _TestCloseWhileConnectingWithTimeoutClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h
    match MakeConnectionTimeout(30_000)
    | let ct: ConnectionTimeout =>
      _tcp_connection = TCPConnection.client(
        TCPConnectAuth(_h.env.root),
        "localhost",
        "9741",
        "",
        this,
        this
        where connection_timeout = ct)
    | let _: ValidationFailure =>
      _h.fail("MakeConnectionTimeout(30_000) should succeed")
    end

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connecting(count: U32) =>
    _tcp_connection.close()

  fun ref _on_connected() =>
    _h.fail("_on_connected should not fire after close")
    _h.complete(false)

  fun ref _on_connection_failure(reason: ConnectionFailureReason) =>
    match reason
    | ConnectionFailedTimeout =>
      _h.fail("Expected non-timeout failure, got ConnectionFailedTimeout")
      _h.complete(false)
    else
      _h.complete(true)
    end

actor \nodoc\ _TestCloseWhileConnectingWithTimeoutListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _client: (_TestCloseWhileConnectingWithTimeoutClient | None) = None

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(_h.env.root),
      "localhost",
      "9741",
      this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestDoNothingServerActor =>
    _TestDoNothingServerActor(fd, _h)

  fun ref _on_closed() =>
    try
      (_client as _TestCloseWhileConnectingWithTimeoutClient).dispose()
    end

  fun ref _on_listening() =>
    _client = _TestCloseWhileConnectingWithTimeoutClient(_h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestCloseWhileConnectingWithTimeoutListener")

class \nodoc\ iso _TestHardCloseWhileConnectingWithTimeout is UnitTest
  """
  Test that hard_close() during the connecting phase with a connect timeout
  armed cancels the timer and reports ConnectionFailedTCP, not
  ConnectionFailedTimeout.
  """
  fun name(): String => "HardCloseWhileConnectingWithTimeout"

  fun apply(h: TestHelper) =>
    let listener = _TestHardCloseWhileConnectingWithTimeoutListener(h)
    h.dispose_when_done(listener)

    h.long_test(5_000_000_000)

actor \nodoc\ _TestHardCloseWhileConnectingWithTimeoutClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h
    match MakeConnectionTimeout(30_000)
    | let ct: ConnectionTimeout =>
      _tcp_connection = TCPConnection.client(
        TCPConnectAuth(_h.env.root),
        "localhost",
        "9742",
        "",
        this,
        this
        where connection_timeout = ct)
    | let _: ValidationFailure =>
      _h.fail("MakeConnectionTimeout(30_000) should succeed")
    end

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connecting(count: U32) =>
    _tcp_connection.hard_close()

  fun ref _on_connected() =>
    _h.fail("_on_connected should not fire after hard_close")
    _h.complete(false)

  fun ref _on_connection_failure(reason: ConnectionFailureReason) =>
    match reason
    | ConnectionFailedTimeout =>
      _h.fail("Expected non-timeout failure, got ConnectionFailedTimeout")
      _h.complete(false)
    else
      _h.complete(true)
    end

actor \nodoc\ _TestHardCloseWhileConnectingWithTimeoutListener
  is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _client: (_TestHardCloseWhileConnectingWithTimeoutClient | None) = None

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(_h.env.root),
      "localhost",
      "9742",
      this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestDoNothingServerActor =>
    _TestDoNothingServerActor(fd, _h)

  fun ref _on_closed() =>
    try
      (_client as _TestHardCloseWhileConnectingWithTimeoutClient).dispose()
    end

  fun ref _on_listening() =>
    _client = _TestHardCloseWhileConnectingWithTimeoutClient(_h)

  fun ref _on_listen_failure() =>
    _h.fail(
      "Unable to open _TestHardCloseWhileConnectingWithTimeoutListener")
