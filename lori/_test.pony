use "ponytest"

actor Main is TestList
  new create(env: Env) =>
    PonyTest(env, this)

  new make() =>
    None

  fun tag tests(test: PonyTest) =>
    test(_PingPong)    

class iso _PingPong is UnitTest
  """
  Test sending and receiving via a simple Ping-Pong application
  """
  fun name(): String => "PingPong"

  fun apply(h: TestHelper) =>
    let pings_to_send: I32 = 100

    let listener = _TestPongerListener(pings_to_send, h)

    h.long_test(5_000_000_000)
    h.dispose_when_done(listener)

actor _TestPinger is TCPConnectionActor
  let state: TCPConnection
  var _pings_to_send: I32
  let _h: TestHelper

  new create(pings_to_send: I32, h: TestHelper) =>
    _pings_to_send = pings_to_send
    _h = h
    state = TCPConnection.client()
    connect("127.0.0.1", "7669", "")

  fun ref self(): TCPConnection =>
    state

  fun ref on_closed() =>
    None

  fun ref on_connected() =>
    if _pings_to_send > 0 then
      send("Ping")
      _pings_to_send = _pings_to_send - 1
    end

  fun ref on_received(data: Array[U8] iso) =>
    if _pings_to_send > 0 then
      send("Ping")
      _pings_to_send = _pings_to_send - 1
    elseif _pings_to_send == 0 then
      _pings_to_send = _pings_to_send - 1
      _h.complete(true)
    else 
      // If we end up here, we got too many Pongs.
      _h.fail("Too many pongs received")
    end

actor _TestPonger is TCPConnectionActor
  let state: TCPConnection
  var _pings_to_receive: I32
  let _h: TestHelper

  new create(state': TCPConnection iso, pings_to_receive: I32, h: TestHelper) =>
    state = consume state'
    _pings_to_receive = pings_to_receive
    _h = h

  fun ref self(): TCPConnection =>
    state

  fun ref on_closed() =>
    None

  fun ref on_connected() =>
    None

  fun ref on_received(data: Array[U8] iso) =>
    send("Pong")
    _pings_to_receive = _pings_to_receive - 1
    if _pings_to_receive == 0 then
      send("Pong")
    end
    if _pings_to_receive < 0 then
      _h.fail("Too many pings received")
    end

actor _TestPongerListener is TCPListenerActor
  let state: TCPListener
  var _pings_to_receive: I32
  let _h: TestHelper
  var _pinger: (_TestPinger | None) = None

  new create(pings_to_receive: I32, h: TestHelper) =>
    _pings_to_receive = pings_to_receive
    _h = h
    state = TCPListener("127.0.0.1", "7669")
    open()

  fun ref self(): TCPListener =>
    state

  fun ref on_accept(state': TCPConnection iso): _TestPonger =>
    _TestPonger(consume state', _pings_to_receive, _h)

  fun ref on_closed() =>
    try 
      (_pinger as _TestPinger).dispose()
    end
 
  fun ref on_listening() =>
    _pinger = _TestPinger(_pings_to_receive, _h)
