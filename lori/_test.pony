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
    test(_TestMute)
    test(_TestOutgoingFails)
    test(_TestPingPong)
    test(_TestSSLPingPong)
    test(_TestBasicExpect)
    test(_TestUnmute)

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

    let listener = _TestPongerListener(port, None, pings_to_send, h)
    h.dispose_when_done(listener)

    h.long_test(5_000_000_000)

class \nodoc\ iso _TestSSLPingPong is UnitTest
  """
  Test sending and receiving via a simple Ping-Pong application
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

    let listener = _TestPongerListener(port, consume sslctx, pings_to_send, h)
    h.dispose_when_done(listener)

    h.long_test(5_000_000_000)

actor \nodoc\ _TestPinger is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  var _pings_to_send: I32
  let _h: TestHelper

  new create(port: String,
    ssl: (SSL iso | None),
    pings_to_send: I32,
    h: TestHelper)
  =>
    _pings_to_send = pings_to_send
    _h = h

    let interceptor: (DataInterceptor ref | None) =
      match consume ssl
      | let s: SSL iso =>
        SSLClientInterceptor(consume s)
      | None =>
        None
      end

    _tcp_connection = TCPConnection.client(
      TCPConnectAuth(h.env.root),
      "localhost",
      port,
      "",
      this,
      this,
      interceptor)
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

  new create(ssl: (SSL iso | None),
    fd: U32,
    pings_to_receive: I32,
    h: TestHelper)
  =>
    _pings_to_receive = pings_to_receive
    _h = h

    let interceptor: (DataInterceptor ref | None) =
      match consume ssl
      | let s: SSL iso =>
        SSLServerInterceptor(consume s)
      | None =>
        None
      end

    _tcp_connection = TCPConnection.server(
      TCPServerAuth(_h.env.root),
      fd,
      this,
      this,
      interceptor)
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
  let _sslctx: (SSLContext | None)
  var _tcp_listener: TCPListener = TCPListener.none()
  var _pings_to_receive: I32
  let _h: TestHelper
  var _pinger: (_TestPinger | None) = None

  new create(port: String,
    sslctx: (SSLContext | None),
    pings_to_receive: I32,
    h: TestHelper)
  =>
    _port = port
    _sslctx = consume sslctx
    _pings_to_receive = pings_to_receive
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(_h.env.root),
      "localhost",
      _port,
      this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestPonger ? =>
    try
      match _sslctx
      | let ctx: SSLContext =>
        _TestPonger(ctx.server()?,
          fd,
          _pings_to_receive,
          _h)
      | None =>
        _TestPonger(None, fd, _pings_to_receive, _h)
      end
    else
      _h.fail("Unable to set up incoming SSL connection")
      _h.complete(false)
      error
    end

  fun ref _on_closed() =>
    try
      (_pinger as _TestPinger).dispose()
    end

  fun ref _on_listening() =>
    try
      match _sslctx
      | let ctx: SSLContext =>
        _pinger = _TestPinger(_port, ctx.client()?, _pings_to_receive, _h)
      | None =>
        _pinger = _TestPinger(_port, None, _pings_to_receive, _h)
      end
    else
      _h.fail("Unable to set up outgoing SSL connection")
      _h.complete(false)
    end

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
