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

    try
      let auth = TCPListenAuth(h.env.root as AmbientAuth)
      let listener = _TestPongerListener(auth, pings_to_send, h)
      h.dispose_when_done(listener)
    end

    h.long_test(5_000_000_000)

actor _TestPinger is TCPConnectionActor
  var _connection: TCPConnection = TCPConnection.none()
  var _pings_to_send: I32
  let _h: TestHelper

  new create(auth: TCPConnectionClientAuth,
    pings_to_send: I32,
    h: TestHelper)
  =>
    _pings_to_send = pings_to_send
    _h = h
    _connection = TCPConnection.client(auth, "127.0.0.1", "7669", "", this)


  fun ref connection(): TCPConnection =>
    _connection

  fun ref on_closed() =>
    None

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
      _pings_to_send = _pings_to_send - 1
      _h.complete(true)
    else
      // If we end up here, we got too many Pongs.
      _h.fail("Too many pongs received")
    end

actor _TestPonger is TCPConnectionActor
  var _connection: TCPConnection = TCPConnection.none()
  var _pings_to_receive: I32
  let _h: TestHelper

  new create(auth: TCPConnectionServerAuth,
    fd: U32,
    pings_to_receive: I32,
    h: TestHelper)
  =>
    _pings_to_receive = pings_to_receive
    _h = h
    _connection = TCPConnection.server(auth, fd, this)

  fun ref connection(): TCPConnection =>
    _connection

  fun ref on_closed() =>
    None

  fun ref on_connected() =>
    None

  fun ref on_received(data: Array[U8] iso) =>
    _connection.send("Pong")
    _pings_to_receive = _pings_to_receive - 1
    if _pings_to_receive == 0 then
      _connection.send("Pong")
    end
    if _pings_to_receive < 0 then
      _h.fail("Too many pings received")
    end

actor _TestPongerListener is TCPListenerActor
  var _listener: TCPListener = TCPListener.none()
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
    try
      let auth = TCPConnectAuth(_h.env.root as AmbientAuth)
      _pinger = _TestPinger(auth, _pings_to_receive, _h)
    end

  fun ref on_failure() =>
    _h.fail("Unable to open _TestPongerListener")
