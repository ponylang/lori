use "constrained_types"
use "pony_test"

class \nodoc\ iso _TestOutgoingFails is UnitTest
  """
  Test that we get a failure callback when an outgoing connection fails
  """
  fun name(): String => "OutgoingFails"

  fun apply(h: TestHelper) =>
    let client = _TestOutgoingFailure(h)
    h.dispose_when_done(client)

    h.long_test(5_000_000_000)

actor \nodoc\ _TestOutgoingFailure
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    _tcp_connection =
      TCPConnection.client(
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

    _tcp_connection =
      TCPConnection.client(
        TCPConnectAuth(h.env.root),
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

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    if _pings_to_send > 0 then
      _tcp_connection.send("Ping")
      _pings_to_send = _pings_to_send - 1
    elseif _pings_to_send == 0 then
      _h.complete(true)
    else
      _h.fail("Too many pongs received")
    end
    KeepReading

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

    _tcp_connection =
      TCPConnection.server(
        TCPServerAuth(_h.env.root),
        fd,
        this,
        this)
    match MakeBufferSize(4)
    | let e: BufferSize => _tcp_connection.buffer_until(e)
    end

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    if _pings_to_receive > 0 then
      _tcp_connection.send("Pong")
      _pings_to_receive = _pings_to_receive - 1
    elseif _pings_to_receive == 0 then
      _tcp_connection.send("Pong")
    else
      _h.fail("Too many pings received")
    end
    KeepReading

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
    _tcp_listener =
      TCPListener(
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

class \nodoc\ iso _TestBasicBufferUntil is UnitTest
  fun name(): String => "BasicBufferUntil"

  fun apply(h: TestHelper) =>
    h.expect_action("server listening")
    h.expect_action("client connected")
    h.expect_action("expected data received")

    let s = _TestBasicBufferUntilListener(h)

    h.dispose_when_done(s)

    h.long_test(5_000_000_000)

actor \nodoc\ _TestBasicBufferUntilClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h
    _tcp_connection =
      TCPConnection.client(
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

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    _h.fail("Client shouldn't get data")
    KeepReading

actor \nodoc\ _TestBasicBufferUntilListener is TCPListenerActor
  let _h: TestHelper
  var _tcp_listener: TCPListener = TCPListener.none()
  var _client: (_TestBasicBufferUntilClient | None) = None

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener =
      TCPListener(
        TCPListenAuth(_h.env.root),
        "localhost",
        "9728",
        this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestBasicBufferUntilServer =>
    _TestBasicBufferUntilServer(fd, _h)

  fun ref _on_closed() =>
    try (_client as _TestBasicBufferUntilClient).dispose() end

  fun ref _on_listening() =>
    _h.complete_action("server listening")
    _client = _TestBasicBufferUntilClient(_h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestBasicBufferUntilListener")

actor \nodoc\ _TestBasicBufferUntilServer
  is (TCPConnectionActor & ServerLifecycleEventReceiver)
  let _h: TestHelper
  var _tcp_connection: TCPConnection = TCPConnection.none()
  var _received_count: U8 = 0

  new create(fd: U32, h: TestHelper) =>
    _h = h
    _tcp_connection =
      TCPConnection.server(
        TCPServerAuth(_h.env.root),
        fd,
        this,
        this)
    match MakeBufferSize(4)
    | let e: BufferSize => _tcp_connection.buffer_until(e)
    end

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
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
    KeepReading

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
    _tcp_listener =
      TCPListener(
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

actor \nodoc\ _TestDoNothingServerActor
  is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()

  new create(fd: U32, h: TestHelper) =>
    _tcp_connection =
      TCPConnection.server(
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
    _tcp_listener =
      TCPListener(
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

class \nodoc\ iso _TestHardCloseDuringReceive is UnitTest
  """
  A hard close from inside `_on_received` must break `_read`'s loop, not fall
  through to another socket read on the fd it just closed.

  The application closing when it has read what it needs is a normal pattern.
  `mute()` + `close()` in `_on_received` routes to `hard_close()`, which
  transitions the connection to `_Closed` while `_read` is still on the stack.
  `_read` must stop on that transition. If it doesn't, it reaches
  `_state.receive()` in `_Closed` — which is `_Unreachable()` — so a
  regression trips that here; in production it read a closed fd, and under
  connection churn a reused blocking fd would hang a scheduler thread.

  `_on_closed` completes the test action before the stray read would run, so a
  regression surfaces as a non-zero process exit from `_Unreachable()`, not a
  failed assertion. `HardCloseAfterFramedReceive` is the assertion-based
  companion for the buffered-delivery path.
  """
  fun name(): String => "HardCloseDuringReceive"

  fun apply(h: TestHelper) =>
    h.expect_action("server listening")
    h.expect_action("server closed during receive")

    let s = _TestHardCloseDuringReceiveListener(h)
    h.dispose_when_done(s)

    h.long_test(5_000_000_000)

actor \nodoc\ _TestHardCloseDuringReceiveListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _client: (_TestHardCloseDuringReceiveClient | None) = None
  var _server: (_TestHardCloseDuringReceiveServer | None) = None

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener =
      TCPListener(
        TCPListenAuth(_h.env.root),
        "localhost",
        "7920",
        this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestHardCloseDuringReceiveServer =>
    let server = _TestHardCloseDuringReceiveServer(fd, _h)
    _server = server
    server

  fun ref _on_closed() =>
    try (_client as _TestHardCloseDuringReceiveClient).dispose() end
    try (_server as _TestHardCloseDuringReceiveServer).dispose() end

  fun ref _on_listening() =>
    _h.complete_action("server listening")
    _client = _TestHardCloseDuringReceiveClient(_h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestHardCloseDuringReceiveListener")

actor \nodoc\ _TestHardCloseDuringReceiveClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h
    _tcp_connection =
      TCPConnection.client(
        TCPConnectAuth(_h.env.root),
        "localhost",
        "7920",
        "",
        this,
        this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    // Give the server data so its `_on_received` fires.
    match \exhaustive\ _tcp_connection.send("ping")
    | let _: SendToken => None
    | let _: SendError =>
      _h.fail("client send() failed")
      _h.complete(false)
    end

actor \nodoc\ _TestHardCloseDuringReceiveServer
  is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper
  var _closed_in_receive: Bool = false

  new create(fd: U32, h: TestHelper) =>
    _h = h
    _tcp_connection =
      TCPConnection.server(
        TCPServerAuth(_h.env.root),
        fd,
        this,
        this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    // Hard close from inside the read callback (see the class docstring).
    _closed_in_receive = true
    _tcp_connection.mute()
    _tcp_connection.close()
    KeepReading

  fun ref _on_closed() =>
    if _closed_in_receive then
      _h.complete_action("server closed during receive")
    end

class \nodoc\ iso _TestHardCloseAfterFramedReceive is UnitTest
  """
  When two framed messages arrive in one socket read and the application
  hard_closes after the first, `_read` must not deliver the second.

  With `buffer_until` framing, `_read`'s inner loop hands over one frame at a
  time from a single buffered read. A `hard_close()` in the first frame's
  `_on_received` transitions the connection to `_Closed`; the loop must stop
  rather than deliver the buffered second frame after `_on_closed` fired. The
  close is unmuted, so `is_live()` — not `_muted` — is what has to stop it.
  The delivery count is checked in a self-behavior that runs after `_read`
  returns, so a regression fails with a clear assertion, not a process exit.

  The two 4-byte frames go out in one `send()`, so on loopback they arrive in a
  single read. A split (not expected here) would leave the second frame unread
  after the close, so the test would pass without exercising the path — it can
  never fail spuriously.
  """
  fun name(): String => "HardCloseAfterFramedReceive"

  fun apply(h: TestHelper) =>
    h.expect_action("only first frame delivered")

    let s = _TestHardCloseAfterFramedReceiveListener(h)
    h.dispose_when_done(s)

    h.long_test(5_000_000_000)

actor \nodoc\ _TestHardCloseAfterFramedReceiveListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _client: (_TestHardCloseAfterFramedReceiveClient | None) = None
  var _server: (_TestHardCloseAfterFramedReceiveServer | None) = None

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener =
      TCPListener(
        TCPListenAuth(_h.env.root),
        "localhost",
        "7921",
        this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestHardCloseAfterFramedReceiveServer =>
    let server = _TestHardCloseAfterFramedReceiveServer(fd, _h)
    _server = server
    server

  fun ref _on_closed() =>
    try (_client as _TestHardCloseAfterFramedReceiveClient).dispose() end
    try (_server as _TestHardCloseAfterFramedReceiveServer).dispose() end

  fun ref _on_listening() =>
    _client = _TestHardCloseAfterFramedReceiveClient(_h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestHardCloseAfterFramedReceiveListener")

actor \nodoc\ _TestHardCloseAfterFramedReceiveClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h
    _tcp_connection =
      TCPConnection.client(
        TCPConnectAuth(_h.env.root),
        "localhost",
        "7921",
        "",
        this,
        this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    // Two 4-byte frames in a single send, so both land in one server read.
    match \exhaustive\ _tcp_connection.send("AAAABBBB")
    | let _: SendToken => None
    | let _: SendError =>
      _h.fail("client send() failed")
      _h.complete(false)
    end

actor \nodoc\ _TestHardCloseAfterFramedReceiveServer
  is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper
  var _received_count: U8 = 0

  new create(fd: U32, h: TestHelper) =>
    _h = h
    _tcp_connection =
      TCPConnection.server(
        TCPServerAuth(_h.env.root),
        fd,
        this,
        this)
    match MakeBufferSize(4)
    | let b: BufferSize => _tcp_connection.buffer_until(b)
    end

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    _received_count = _received_count + 1
    if _received_count == 1 then
      _h.assert_eq[String]("AAAA", String.from_array(consume data))
      // Unmuted hard close inside the first frame's callback. The buffered
      // second frame must not be delivered next. The count is checked below in
      // a behavior that runs after `_read` returns.
      _tcp_connection.hard_close()
      _check_delivery_count()
    end
    KeepReading

  be _check_delivery_count() =>
    if _received_count == 1 then
      _h.complete_action("only first frame delivered")
    else
      _h.fail("second frame delivered after hard_close()")
    end
