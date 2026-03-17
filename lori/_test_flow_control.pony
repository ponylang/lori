use "pony_test"

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
