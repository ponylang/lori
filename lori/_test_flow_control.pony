use "constrained_types"
use "files"
use "pony_test"
use "ssl/net"

class \nodoc\ iso _TestMute is UnitTest
  """
  Test that the `mute` behavior stops us from reading incoming data. The
  test assumes that send/recv works correctly and that the absence of
  data received is because we muted the connection.

  Test works as follows:

  Once an incoming connection is established, we set mute on it and then verify
  that within a 5 second long test the `_on_received` callback is not triggered.
  A timeout is considered passing; `_on_received` being called is grounds for a
  failure.
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

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
     _tcp_connection.send("it's sad that you won't ever read this")
     _h.complete_action("client sent data")
    KeepReading

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

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    _h.fail("server should not receive data")
    _h.complete(false)
    KeepReading

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

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
     _tcp_connection.send("i'm happy you will receive this")
     _h.complete_action("client sent data")
    KeepReading

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

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    _h.complete(true)
    KeepReading

class \nodoc\ iso _TestSSLMute is UnitTest
  """
  Test that `mute()` called from `_on_received` stops delivery of the decrypted
  messages still sitting in the SSL session, and that `unmute()` delivers them.

  A single `send()` of 20 bytes crosses the wire as one SSL record. With
  `buffer_until(4)` the SSL session has five 4-byte messages to hand over from
  that one TCP read. The server mutes on the first, the second, and the fifth; a
  timer does each unmuting. All five must arrive, in order, across the three
  pauses — muting holds messages, it doesn't drop or reorder them.

  The second and fifth mutes are the interesting ones. The second lands on a
  message the first `unmute()` went back to the session for. The fifth is on the
  last message, so it mutes with nothing left to hold, and the next read has to
  find an empty session and carry on. To show that it did, the server sends
  "PING" after its third `unmute()` and the test completes when the client's
  "PONG" arrives as a sixth message.

  Five things fail the test: a message arriving while muted, a message arriving
  out of order, the last message arriving without three unmutes, a "PONG" that
  never arrives because the empty session wedged the read path, and the timeout
  that a mute which never resumed reading would hit.

  The test uses no `expect_action`: completing every expected action passes a
  long test on its own, and every action this test could name happens before
  the held messages arrive.
  """
  fun name(): String => "SSLMute"

  fun apply(h: TestHelper) ? =>
    let port = "9778"
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

    let listener = _TestSSLMuteListener(port, consume sslctx, h)
    h.dispose_when_done(listener)

    h.long_test(15_000_000_000)

actor \nodoc\ _TestSSLMuteListener is TCPListenerActor
  let _port: String
  let _sslctx: SSLContext val
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _client: (_TestSSLMuteClient | None) = None
  var _server: (_TestSSLMuteServer | None) = None

  new create(port: String, sslctx: SSLContext val, h: TestHelper) =>
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

  fun ref _on_accept(fd: U32): _TestSSLMuteServer =>
    let s = _TestSSLMuteServer(_sslctx, fd, _h)
    _server = s
    s

  fun ref _on_listening() =>
    _client = _TestSSLMuteClient(_port, _sslctx, _h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestSSLMuteListener")
    _h.complete(false)

  be dispose() =>
    try (_client as _TestSSLMuteClient).dispose() end
    try (_server as _TestSSLMuteServer).dispose() end
    _tcp_listener.close()

actor \nodoc\ _TestSSLMuteClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(port: String, sslctx: SSLContext val, h: TestHelper) =>
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
    // One SSL record holding five 4-byte messages.
    _tcp_connection.send("AAAABBBBCCCCDDDDEEEE")

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    // The server pings once it has unmuted for the last time. Answering it
    // proves its read path still works after a resume that found nothing.
    if String.from_iso_array(consume data) == "PING" then
      _tcp_connection.send("PONG")
    end
    KeepReading

  fun ref _on_connection_failure(reason: ConnectionFailureReason) =>
    _h.fail("client connect failed")
    _h.complete(false)

actor \nodoc\ _TestSSLMuteServer
  is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper
  let _chunks: Array[String] val =
    recover val ["AAAA"; "BBBB"; "CCCC"; "DDDD"; "EEEE"; "PONG"] end
  // The messages the server mutes on: the first, the second (which pauses a
  // poll that was itself a resume) and the fifth (which pauses with nothing
  // left to hold).
  let _mute_on: Array[USize] val = recover val [1; 2; 5] end
  var _muted: Bool = false
  var _received: USize = 0
  var _unmutes: USize = 0

  new create(sslctx: SSLContext val, fd: U32, h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.ssl_server(
      TCPServerAuth(_h.env.root),
      sslctx,
      fd,
      this,
      this)
    match \exhaustive\ MakeBufferSize(4)
    | let b: BufferSize => _tcp_connection.buffer_until(b)
    | let _: ValidationFailure =>
      _h.fail("MakeBufferSize(4) should succeed")
      _h.complete(false)
    end

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    if _muted then
      _h.fail("server received data while muted")
      _h.complete(false)
      return KeepReading
    end

    _received = _received + 1

    let got: String val = String.from_iso_array(consume data)
    let want = try _chunks(_received - 1)? else "" end
    if got != want then
      _h.fail("message " + _received.string() + " was '" + got + "', wanted '"
        + want + "'")
      _h.complete(false)
      return KeepReading
    end

    if _mute_on.contains(_received) then
      _muted = true
      _tcp_connection.mute()
      match MakeTimerDuration(500)
      | let d: TimerDuration =>
        match _tcp_connection.set_timer(d)
        | let _: TimerToken => None
        | let _: SetTimerError =>
          _h.fail("set_timer returned error")
          _h.complete(false)
        end
      | let _: ValidationFailure =>
        _h.fail("MakeTimerDuration(500) should succeed")
        _h.complete(false)
      end
    elseif _received == _chunks.size() then
      if _unmutes == _mute_on.size() then
        _h.complete(true)
      else
        _h.fail("all messages arrived after " + _unmutes.string()
          + " unmutes, wanted " + _mute_on.size().string())
        _h.complete(false)
      end
    end
    KeepReading

  fun ref _on_timer(token: TimerToken) =>
    _unmutes = _unmutes + 1
    _muted = false
    _tcp_connection.unmute()
    if _unmutes == _mute_on.size() then
      // That last unmute resumed a poll with nothing held. Ask the client for
      // one more message: it can only arrive if the read path survived.
      _tcp_connection.send("PING")
    end

class \nodoc\ iso _TestSSLMuteCloseDropsHeld is UnitTest
  """
  Test that closing a muted SSL connection drops the messages the `mute()` was
  holding, and closes rather than hanging.

  `close()` on a muted connection hard closes, because a muted connection isn't
  reading and so can never see the peer's FIN. The hard close disposes the SSL
  session, and the decrypted messages still inside it go with it.

  The client sends one SSL record holding three 4-byte messages. The server
  mutes on the first, so the second and third are held. A timer then closes the
  connection. `_on_closed` must fire, and neither held message may be delivered.

  A `close()` that went the graceful route instead would leave a muted
  connection waiting on a FIN it will never read, and the test would time out.
  """
  fun name(): String => "SSLMuteCloseDropsHeld"

  fun apply(h: TestHelper) ? =>
    let port = "9779"
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

    h.expect_action("server received")
    h.expect_action("server closed")

    let listener = _TestSSLMuteCloseListener(port, consume sslctx, h)
    h.dispose_when_done(listener)

    h.long_test(15_000_000_000)

actor \nodoc\ _TestSSLMuteCloseListener is TCPListenerActor
  let _port: String
  let _sslctx: SSLContext val
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _client: (_TestSSLMuteCloseClient | None) = None
  var _server: (_TestSSLMuteCloseServer | None) = None

  new create(port: String, sslctx: SSLContext val, h: TestHelper) =>
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

  fun ref _on_accept(fd: U32): _TestSSLMuteCloseServer =>
    let s = _TestSSLMuteCloseServer(_sslctx, fd, _h)
    _server = s
    s

  fun ref _on_listening() =>
    _client = _TestSSLMuteCloseClient(_port, _sslctx, _h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestSSLMuteCloseListener")
    _h.complete(false)

  be dispose() =>
    try (_client as _TestSSLMuteCloseClient).dispose() end
    try (_server as _TestSSLMuteCloseServer).dispose() end
    _tcp_listener.close()

actor \nodoc\ _TestSSLMuteCloseClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(port: String, sslctx: SSLContext val, h: TestHelper) =>
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
    // One SSL record holding three 4-byte messages.
    _tcp_connection.send("AAAABBBBCCCC")

  fun ref _on_connection_failure(reason: ConnectionFailureReason) =>
    _h.fail("client connect failed")
    _h.complete(false)

actor \nodoc\ _TestSSLMuteCloseServer
  is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper
  var _received: USize = 0

  new create(sslctx: SSLContext val, fd: U32, h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.ssl_server(
      TCPServerAuth(_h.env.root),
      sslctx,
      fd,
      this,
      this)
    match \exhaustive\ MakeBufferSize(4)
    | let b: BufferSize => _tcp_connection.buffer_until(b)
    | let _: ValidationFailure =>
      _h.fail("MakeBufferSize(4) should succeed")
      _h.complete(false)
    end

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    _received = _received + 1

    if _received > 1 then
      _h.fail("message " + _received.string()
        + " was delivered; mute should have held it and close dropped it")
      return KeepReading
    end

    _h.complete_action("server received")
    _tcp_connection.mute()
    match MakeTimerDuration(500)
    | let d: TimerDuration =>
      match _tcp_connection.set_timer(d)
      | let _: TimerToken => None
      | let _: SetTimerError =>
        _h.fail("set_timer returned error")
        _h.complete(false)
      end
    | let _: ValidationFailure =>
      _h.fail("MakeTimerDuration(500) should succeed")
      _h.complete(false)
    end
    KeepReading

  fun ref _on_timer(token: TimerToken) =>
    _tcp_connection.close()

  fun ref _on_closed() =>
    _h.complete_action("server closed")
