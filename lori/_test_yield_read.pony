use "constrained_types"
use "pony_test"

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
