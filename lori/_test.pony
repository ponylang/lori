use "pony_test"

actor Main is TestList
  new create(env: Env) =>
    PonyTest(env, this)

  new make() =>
    None

  fun tag tests(test: PonyTest) =>
    ifdef windows then
      test(_OutgoingFails)
      test(_CanListen)
      test(_PingPong)
      test(_TestBasicExpect)
    else
      test(_OutgoingFails)
      test(_CanListen)
      test(_PingPong)
      test(_TestBasicExpect)
    end

class iso _OutgoingFails is UnitTest
  """
  Test that we get a failure callback when an outgoing connection fails
  """
  fun name(): String => "OutgoingFails"

  fun apply(h: TestHelper) =>
    let auth = h.env.root
    let client = _TestOutgoingFailure(TCPConnectAuth(auth), h)
    h.dispose_when_done(client)

    h.long_test(5_000_000_000)

actor _TestOutgoingFailure is TCPClientActor
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(auth: TCPConnectAuth, h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.client(auth, "127.0.0.1", "3245", "", this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _h.fail("on_connected for a connection that should have failed")
    _h.complete(false)

  fun ref _on_connection_failure() =>
    _h.complete(true)

class iso _PingPong is UnitTest
  """
  Test sending and receiving via a simple Ping-Pong application
  """
  fun name(): String => "PingPong"

  fun apply(h: TestHelper) =>
    let pings_to_send: I32 = 100

    let auth = TCPListenAuth(h.env.root)
    let listener = _TestPongerListener(auth, pings_to_send, h)
    h.dispose_when_done(listener)

    h.long_test(5_000_000_000)

actor _TestPinger is TCPClientActor
  var _tcp_connection: TCPConnection = TCPConnection.none()
  var _pings_to_send: I32
  let _h: TestHelper

  new create(auth: TCPConnectAuth,
    pings_to_send: I32,
    h: TestHelper)
  =>
    _pings_to_send = pings_to_send
    _h = h
    _tcp_connection = TCPConnection.client(auth, "127.0.0.1", "7664", "", this)
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

actor _TestPonger is TCPServerActor
  var _tcp_connection: TCPConnection = TCPConnection.none()
  var _pings_to_receive: I32
  let _h: TestHelper

  new create(auth: TCPServerAuth,
    fd: U32,
    pings_to_receive: I32,
    h: TestHelper)
  =>
    _pings_to_receive = pings_to_receive
    _h = h
    _tcp_connection = TCPConnection.server(auth, fd, this)
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

actor _TestPongerListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  var _pings_to_receive: I32
  let _h: TestHelper
  var _pinger: (_TestPinger | None) = None
  let _server_auth: TCPServerAuth

  new create(listener_auth: TCPListenAuth,
    pings_to_receive: I32,
    h: TestHelper)
  =>
    _pings_to_receive = pings_to_receive
    _h = h
    _server_auth = TCPServerAuth(listener_auth)
    _tcp_listener = TCPListener(listener_auth, "127.0.0.1", "7664", this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestPonger =>
    _TestPonger(_server_auth, fd, _pings_to_receive, _h)

  fun ref _on_closed() =>
    try
      (_pinger as _TestPinger).dispose()
    end

  fun ref _on_listening() =>
    let auth = TCPConnectAuth(_h.env.root)
    _pinger = _TestPinger(auth, _pings_to_receive, _h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestPongerListener")

class iso _TestBasicExpect is UnitTest
  fun name(): String => "TestBasicExpect"

  fun apply(h: TestHelper) =>
    h.expect_action("server listening")
    h.expect_action("client connected")
    h.expect_action("expected data received")

    let la = TCPListenAuth(h.env.root)
    let ca = TCPConnectAuth(h.env.root)
    let s = _TestBasicExpectListener(la, ca, h)

    h.dispose_when_done(s)

    h.long_test(2_000_000_000)

actor _TestBasicExpectClient is TCPClientActor
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(auth: TCPConnectAuth, h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.client(auth, "127.0.0.1", "9728", "", this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _h.complete_action("client connected")
    _tcp_connection.send("hi there, how are you???")

  fun ref _on_received(data: Array[U8] iso) =>
    _h.fail("Client shouldn't get data")

actor _TestBasicExpectListener is TCPListenerActor
  let _h: TestHelper
  var _tcp_listener: TCPListener = TCPListener.none()
  let _server_auth: TCPServerAuth
  let _client_auth: TCPConnectAuth
  var _client: (_TestBasicExpectClient | None) = None

  new create(listener_auth: TCPListenAuth,
    client_auth: TCPConnectAuth,
    h: TestHelper)
  =>
    _h = h
    _client_auth = client_auth
    _server_auth = TCPServerAuth(listener_auth)
    _tcp_listener = TCPListener(listener_auth, "127.0.0.1", "9728", this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestBasicExpectServer =>
    _TestBasicExpectServer(_server_auth, fd, _h)

  fun ref _on_closed() =>
    try (_client as _TestBasicExpectClient).dispose() end

  fun ref _on_listening() =>
    _h.complete_action("server listening")
    _client =_TestBasicExpectClient(_client_auth, _h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestBasicExpectListener")

actor _TestBasicExpectServer is TCPServerActor
  let _h: TestHelper
  var _tcp_connection: TCPConnection = TCPConnection.none()
  var _received_count: U8 = 0

  new create(auth: TCPServerAuth, fd: U32, h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.server(auth, fd, this)
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

class iso _CanListen is UnitTest
  """
  Test that we can listen on a socket for incoming connections and that the
  `_on_listening` callback is correctly called.
  """
  fun name(): String => "CanListen"

  fun apply(h: TestHelper) =>
    let auth = TCPListenAuth(h.env.root)
    let listener = _TestCanListenListener(auth, h)
    h.dispose_when_done(listener)

    h.long_test(5_000_000_000)

actor _TestCanListenListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  let _server_auth: TCPServerAuth

  new create(listener_auth: TCPListenAuth, h: TestHelper) =>
    _h = h
    _server_auth = TCPServerAuth(listener_auth)
    _tcp_listener = TCPListener(listener_auth, "127.0.0.1", "5786", this)

  fun ref _on_accept(fd: U32): _TestDoNothingServerActor =>
    _h.fail("_on_accept shouldn't be called")
    _h.complete(false)
    _TestDoNothingServerActor(_server_auth, fd)

  fun ref _on_listen_failure() =>
    _h.fail("listening failed")
    _h.complete(false)

  fun ref _on_listening() =>
    _h.complete(true)

  fun ref _listener(): TCPListener =>
    _tcp_listener

actor _TestDoNothingServerActor is TCPServerActor
  var _tcp_connection: TCPConnection = TCPConnection.none()

  new create(auth: TCPServerAuth, fd: U32) =>
    _tcp_connection = TCPConnection.server(auth, fd, this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection
