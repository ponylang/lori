use "ponytest"


actor Main is TestList
  new create(env: Env) =>
    PonyTest(env, this)

  new make() =>
    None

  fun tag tests(test: PonyTest) =>
    test(_BitSet)
    test(_TCPConnectionState)
    test(_PingPong)
    test(_TestBasicExpect)

class iso _BitSet is UnitTest
  fun name(): String => "BitSet"

  fun apply(h: TestHelper) =>
    var x: U32 = 0

    h.assert_false(BitSet.is_set(x, 0))
    x = BitSet.set(x, 0)
    h.assert_true(BitSet.is_set(x, 0))
    x = BitSet.set(x, 0)
    h.assert_true(BitSet.is_set(x, 0))

    h.assert_false(BitSet.is_set(x, 1))
    x = BitSet.set(x, 1)
    h.assert_true(BitSet.is_set(x, 0))
    h.assert_true(BitSet.is_set(x, 1))

    x = BitSet.unset(x, 0)
    h.assert_false(BitSet.is_set(x, 0))
    h.assert_true(BitSet.is_set(x, 1))

class iso _TCPConnectionState is UnitTest
  """
  Test that connection state works correctly
  """
  fun name(): String => "ConnectionState"

  fun apply(h: TestHelper) =>
    // TODO: turn this into several different tests
    let a = TCPConnection.none()

    h.assert_false(a.is_open())
    a.open()
    h.assert_true(a.is_open())
    a.close()
    h.assert_true(a.is_closed())
    a.open()
    h.assert_true(a.is_open())
    h.assert_true(a.is_writeable())
    h.assert_true(a.is_open())
    a.throttled()
    h.assert_true(a.is_throttled())
    h.assert_false(a.is_writeable())
    h.assert_true(a.is_open())
    a.writeable()
    h.assert_true(a.is_writeable())
    a.writeable()
    h.assert_true(a.is_writeable())

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
  var _connection: TCPConnection = TCPConnection.none()
  var _pings_to_send: I32
  let _h: TestHelper

  new create(auth: OutgoingTCPAuth,
    pings_to_send: I32,
    h: TestHelper)
  =>
    _pings_to_send = pings_to_send
    _h = h
    _connection = TCPConnection.client(auth, "127.0.0.1", "7669", "", this)


  fun ref connection(): TCPConnection =>
    _connection

  fun ref on_connected() =>
    if _pings_to_send > 0 then
      _connection.send("Ping")
      _pings_to_send = _pings_to_send - 1
    end

  fun ref on_received(data: Array[U8] iso) =>
    if _pings_to_send > 0 then
      _connection.send("Ping")
      _pings_to_send = _pings_to_send - 1
    elseif _pings_to_send == 0 then
      _h.complete(true)
    else
      _h.fail("Too many pongs received")
    end

actor _TestPonger is TCPServerActor
  var _connection: TCPConnection = TCPConnection.none()
  var _pings_to_receive: I32
  let _h: TestHelper

  new create(auth: IncomingTCPAuth,
    fd: U32,
    pings_to_receive: I32,
    h: TestHelper)
  =>
    _pings_to_receive = pings_to_receive
    _h = h
    _connection = TCPConnection.server(auth, fd, this)

  fun ref connection(): TCPConnection =>
    _connection

  fun ref on_received(data: Array[U8] iso) =>
    if _pings_to_receive > 0 then
      _connection.send("Pong")
      _pings_to_receive = _pings_to_receive - 1
    elseif _pings_to_receive == 0 then
      _connection.send("Pong")
    else
      _h.fail("Too many pings received")
    end

actor _TestPongerListener is TCPListenerActor
  var _listener: TCPListener = TCPListener.none()
  var _pings_to_receive: I32
  let _h: TestHelper
  var _pinger: (_TestPinger | None) = None
  let _server_auth: TCPServerAuth

  new create(listener_auth: TCPListenerAuth,
    pings_to_receive: I32,
    h: TestHelper)
  =>
    _pings_to_receive = pings_to_receive
    _h = h
    _server_auth = TCPServerAuth(listener_auth)
    _listener = TCPListener(listener_auth, "127.0.0.1", "7669", this)

  fun ref listener(): TCPListener =>
    _listener

  fun ref on_accept(fd: U32): _TestPonger =>
    _TestPonger(_server_auth, fd, _pings_to_receive, _h)

  fun ref on_closed() =>
    try
      (_pinger as _TestPinger).dispose()
    end

  fun ref on_listening() =>
    let auth = TCPConnectAuth(_h.env.root)
    _pinger = _TestPinger(auth, _pings_to_receive, _h)

  fun ref on_failure() =>
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
  var _connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(auth: OutgoingTCPAuth, h: TestHelper) =>
    _h = h
    _connection = TCPConnection.client(auth, "127.0.0.1", "7670", "", this)

  fun ref connection(): TCPConnection =>
    _connection

  fun ref on_connected() =>
    _h.complete_action("client connected")
    _connection.send("hi there, how are you???")

  fun ref on_received(data: Array[U8] iso) =>
    _h.fail("Client shouldn't get data")

actor _TestBasicExpectListener is TCPListenerActor
  let _h: TestHelper
  var _listener: TCPListener = TCPListener.none()
  let _server_auth: TCPServerAuth
  let _client_auth: TCPConnectAuth
  var _client: (_TestBasicExpectClient | None) = None

  new create(listener_auth: TCPListenerAuth,
    client_auth: TCPConnectAuth,
    h: TestHelper)
  =>
    _h = h
    _client_auth = client_auth
    _server_auth = TCPServerAuth(listener_auth)
    _listener = TCPListener(listener_auth, "127.0.0.1", "7670", this)

  fun ref listener(): TCPListener =>
    _listener

  fun ref on_accept(fd: U32): _TestBasicExpectServer =>
    _TestBasicExpectServer(_server_auth, fd, _h)

  fun ref on_closed() =>
    try (_client as _TestBasicExpectClient).dispose() end

  fun ref on_listening() =>
    _h.complete_action("server listening")
    _client =_TestBasicExpectClient(_client_auth, _h)

  fun ref on_failure() =>
    _h.fail("Unable to open _TestBasicExpectListener")

actor _TestBasicExpectServer is TCPServerActor
  let _h: TestHelper
  var _connection: TCPConnection = TCPConnection.none()
  var _received_count: U8 = 0

  new create(auth: IncomingTCPAuth, fd: U32, h: TestHelper) =>
    _h = h
    _connection = TCPConnection.server(auth, fd, this)
    try _connection.expect(4)? end

  fun ref connection(): TCPConnection =>
    _connection

  fun ref on_received(data: Array[U8] iso) =>
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
      _connection.close()
    end
