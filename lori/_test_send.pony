use "constrained_types"
use "files"
use "pony_test"
use "ssl/net"

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
    match MakeBufferSize(13)
    | let e: BufferSize => _tcp_connection.buffer_until(e)
    end

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    _h.assert_eq[String]("Hello, world!", String.from_array(consume data))
    _h.complete_action("data verified")
    _tcp_connection.close()
    KeepReading

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
    match MakeBufferSize(10)
    | let e: BufferSize => _tcp_connection.buffer_until(e)
    end

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    _h.assert_eq[String]("Helloworld", String.from_array(consume data))
    _h.complete_action("data verified")
    _tcp_connection.close()
    KeepReading

class \nodoc\ iso _TestSendPerTokenCompletion is UnitTest
  """
  Overlapping sends each get exactly one `_on_sent`, in send order.

  The client mutes with a tiny SO_RCVBUF so the pipe fills. The server (sender)
  makes three tiny sends that drain immediately (tokens 1-3 -> `_on_sent`), then
  a 256 KiB send that partial-writes and stays pending (token 4). When the pipe
  drains enough to unthrottle, the server makes a second 256 KiB send from
  `_on_unthrottled` -- the one window where `_writeable` is true while earlier
  data is still queued -- so tokens 4 and 5 are in the pending queue at once.
  The client then drains everything.

  Asserts every returned token fires `_on_sent` exactly once, in ascending id
  order (proving none was lost or reordered). A single shared pending token
  would let the second pending send overwrite the first, so token 4 never fires
  `_on_sent`: the ordering assertion then sees id 5 where it expects 4.

  POSIX only -- provoking write backpressure with a fixed payload requires
  honoring the small SO_SNDBUF/SO_RCVBUF, which Windows loopback ignores. See
  the note on `_TestBackpressureDrain`.
  """
  fun name(): String => "SendPerTokenCompletion"

  fun ref apply(h: TestHelper) =>
    let listener = _TestSendPerTokenListener(h)
    h.dispose_when_done(listener)
    h.long_test(30_000_000_000)

actor \nodoc\ _TestSendPerTokenListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _server: (_TestSendPerTokenServer | None) = None
  var _client: (_TestSendPerTokenClient | None) = None

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(_h.env.root),
      ifdef linux then "127.0.0.2" else "localhost" end,
      "7910",
      this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestSendPerTokenServer =>
    let s = _TestSendPerTokenServer(fd, _h, this)
    _server = s
    s

  fun ref _on_listen_failure() =>
    _h.fail("listener failed to start")

  fun ref _on_listening() =>
    _client = _TestSendPerTokenClient(_h)

  fun ref _on_closed() =>
    try (_client as _TestSendPerTokenClient).dispose() end
    try (_server as _TestSendPerTokenServer).dispose() end

  be unmute_client() =>
    try (_client as _TestSendPerTokenClient).resume_reading() end

actor \nodoc\ _TestSendPerTokenClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.client(
      TCPConnectAuth(_h.env.root),
      ifdef linux then "127.0.0.2" else "localhost" end,
      "7910",
      "",
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    // Tiny receive buffer + muted reads so the sender's pipe fills fast.
    _tcp_connection.set_so_rcvbuf(4096)
    _tcp_connection.mute()
    _tcp_connection.send("ready")

  fun ref _on_connection_failure(reason: ConnectionFailureReason) =>
    _h.fail("client connect failed")

  be resume_reading() =>
    _tcp_connection.unmute()

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    None
    KeepReading

actor \nodoc\ _TestSendPerTokenServer
  is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper
  let _listener: _TestSendPerTokenListener
  let _total_sends: USize = 5
  var _started: Bool = false
  var _unmuted_client: Bool = false
  var _resumed: Bool = false
  embed _returned: Array[USize] = _returned.create()
  embed _completed: Array[USize] = _completed.create()
  var _expected_next: USize = 1

  new create(fd: U32, h: TestHelper, listener: _TestSendPerTokenListener) =>
    _h = h
    _listener = listener
    _tcp_connection = TCPConnection.server(
      TCPServerAuth(_h.env.root),
      fd,
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_started() =>
    // Frame the client's "ready" (5 bytes).
    match MakeBufferSize(5)
    | let b: BufferSize => _tcp_connection.buffer_until(b)
    else _Unreachable()
    end

  fun ref _record_send(r: (SendToken | SendError)) =>
    match r
    | let t: SendToken => _returned.push(t.id)
    | let _: SendError => _h.fail("send() returned an error while flooding")
    end

  fun ref _large(): Array[U8] val =>
    recover val Array[U8].init('x', 256_000) end

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    if _started then return KeepReading end
    _started = true
    // Small send buffer so the pipe is tiny and backpressure comes fast.
    _tcp_connection.set_so_sndbuf(16384)
    // Three tiny sends fit the pipe and drain immediately -> _on_sent (1-3).
    _record_send(_tcp_connection.send("t1"))
    _record_send(_tcp_connection.send("t2"))
    _record_send(_tcp_connection.send("t3"))
    // One large send that partial-writes and stays pending (token 4).
    _record_send(_tcp_connection.send(_large()))
    KeepReading

  fun ref _on_throttled() =>
    if not _unmuted_client then
      _unmuted_client = true
      _listener.unmute_client()
    end

  fun ref _on_unthrottled() =>
    if not _resumed then
      _resumed = true
      // Token 4 (256 KiB) is still pending: _on_unthrottled fires before this
      // event drains, and 256 KiB won't clear in a single write. This send
      // (token 5) appends, so the pending queue holds 4 and 5 simultaneously.
      _record_send(_tcp_connection.send(_large()))
    end

  fun ref _on_sent(token: SendToken) =>
    _h.assert_eq[USize](_expected_next, token.id,
      "_on_sent fired out of order or with a gap")
    _expected_next = _expected_next + 1
    _completed.push(token.id)
    if _completed.size() == _total_sends then
      _h.assert_eq[USize](_returned.size(), _completed.size(),
        "every returned token must fire _on_sent exactly once")
      _tcp_connection.close()
      _h.complete(true)
    end

  fun ref _on_send_failed(token: SendToken) =>
    _h.fail("no send should fail in the drain scenario")

class \nodoc\ iso _TestSendSSLLargeSingleSend is UnitTest
  """
  A single large SSL send is delivered in full across multiple writeable
  events.

  The client makes one 256 KiB SSL send and nothing after it; the server
  echoes each decrypted chunk. A tiny SO_RCVBUF on both ends forces the
  ciphertext to partial-write, so it can only reach the wire in pieces on
  successive writeable events. The echo returns all 256 KiB only if the
  pending-write drain loop keeps flushing that one send's queued ciphertext
  as the socket clears, so the test exercises multi-write drain of a single
  SSL send.
  """
  fun name(): String => "SendSSLLargeSingleSend"

  fun apply(h: TestHelper) ? =>
    let port = "7911"
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

    let listener = _TestSendSSLLargeSingleSendListener(port, consume sslctx, h)
    h.dispose_when_done(listener)

    h.long_test(30_000_000_000)

actor \nodoc\ _TestSendSSLLargeSingleSendListener is TCPListenerActor
  let _port: String
  let _sslctx: SSLContext val
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _client: (_TestSendSSLLargeSingleSendClient | None) = None
  var _server: (_TestSendSSLLargeSingleSendServer | None) = None

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

  fun ref _on_accept(fd: U32): _TestSendSSLLargeSingleSendServer =>
    let s = _TestSendSSLLargeSingleSendServer(_sslctx, fd, _h)
    _server = s
    s

  fun ref _on_closed() =>
    try (_client as _TestSendSSLLargeSingleSendClient).dispose() end
    try (_server as _TestSendSSLLargeSingleSendServer).dispose() end

  fun ref _on_listening() =>
    _client = _TestSendSSLLargeSingleSendClient(_port, _sslctx, _h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestSendSSLLargeSingleSendListener")

actor \nodoc\ _TestSendSSLLargeSingleSendClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper
  let _expected: USize = 262144
  var _received: USize = 0
  var _corrupt: Bool = false

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
    _tcp_connection.set_so_rcvbuf(4096)
    match _tcp_connection.send(recover val Array[U8].init('x', _expected) end)
    | let _: SendToken => None
    | let _: SendError =>
      _h.fail("client send failed")
      _h.complete(false)
    end

  fun ref _on_connection_failure(reason: ConnectionFailureReason) =>
    _h.fail("client connect failed")

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    let d: Array[U8] val = consume data
    for b in d.values() do
      if b != 'x' then _corrupt = true end
    end
    _received = _received + d.size()
    if _received == _expected then
      _h.assert_false(_corrupt, "echoed bytes must all be 'x'")
      _tcp_connection.close()
      _h.complete(true)
    elseif _received > _expected then
      _h.fail("received more bytes than were sent")
      _h.complete(false)
    end
    KeepReading

actor \nodoc\ _TestSendSSLLargeSingleSendServer
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

  fun ref _on_started() =>
    _tcp_connection.set_so_rcvbuf(4096)

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    match _tcp_connection.send(consume data)
    | let _: SendToken => None
    | let _: SendError => _h.fail("server echo failed")
    end
    KeepReading

class \nodoc\ iso _TestSendMidFlightDropBoundary is UnitTest
  """
  On a mid-flight drop, the `_on_sent` / `_on_send_failed` split is a clean
  boundary: every accepted send fires exactly one of the two, in a prefix of
  `_on_sent` (bytes that reached the OS) followed by a suffix of
  `_on_send_failed` (bytes that did not).

  Same backpressure setup as `SendPerTokenCompletion`: three tiny sends drain
  to `_on_sent` (tokens 1-3), a 256 KiB send stays pending (token 4), then a
  second 256 KiB send from `_on_unthrottled` (token 5) leaves 4 and 5 pending
  at once. Instead of draining, the server `hard_close()`s immediately after
  the second send.

  Asserts each of the five tokens fires exactly one terminal callback (none
  both, none neither), that both pending sends (4 and 5) fire `_on_send_failed`,
  that `max(_on_sent id) < min(_on_send_failed id)`, and that `_on_send_failed`
  arrives after `_on_closed`. A single shared pending token would keep only the
  last one, so token 4 would get neither callback.

  POSIX only, for the same reason as `SendPerTokenCompletion`.
  """
  fun name(): String => "SendMidFlightDropBoundary"

  fun ref apply(h: TestHelper) =>
    let listener = _TestSendMidFlightDropListener(h)
    h.dispose_when_done(listener)
    h.long_test(30_000_000_000)

actor \nodoc\ _TestSendMidFlightDropListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _server: (_TestSendMidFlightDropServer | None) = None
  var _client: (_TestSendMidFlightDropClient | None) = None

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(_h.env.root),
      ifdef linux then "127.0.0.2" else "localhost" end,
      "7912",
      this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestSendMidFlightDropServer =>
    let s = _TestSendMidFlightDropServer(fd, _h, this)
    _server = s
    s

  fun ref _on_listen_failure() =>
    _h.fail("listener failed to start")

  fun ref _on_listening() =>
    _client = _TestSendMidFlightDropClient(_h)

  fun ref _on_closed() =>
    try (_client as _TestSendMidFlightDropClient).dispose() end
    try (_server as _TestSendMidFlightDropServer).dispose() end

  be unmute_client() =>
    try (_client as _TestSendMidFlightDropClient).resume_reading() end

actor \nodoc\ _TestSendMidFlightDropClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.client(
      TCPConnectAuth(_h.env.root),
      ifdef linux then "127.0.0.2" else "localhost" end,
      "7912",
      "",
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _tcp_connection.set_so_rcvbuf(4096)
    _tcp_connection.mute()
    _tcp_connection.send("ready")

  fun ref _on_connection_failure(reason: ConnectionFailureReason) =>
    _h.fail("client connect failed")

  be resume_reading() =>
    _tcp_connection.unmute()

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    None
    KeepReading

actor \nodoc\ _TestSendMidFlightDropServer
  is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper
  let _listener: _TestSendMidFlightDropListener
  let _total_sends: USize = 5
  var _started: Bool = false
  var _unmuted_client: Bool = false
  var _resumed: Bool = false
  var _closed: Bool = false
  embed _returned: Array[USize] = _returned.create()
  embed _sent_ids: Array[USize] = _sent_ids.create()
  embed _failed_ids: Array[USize] = _failed_ids.create()

  new create(fd: U32, h: TestHelper,
    listener: _TestSendMidFlightDropListener)
  =>
    _h = h
    _listener = listener
    _tcp_connection = TCPConnection.server(
      TCPServerAuth(_h.env.root),
      fd,
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_started() =>
    match MakeBufferSize(5)
    | let b: BufferSize => _tcp_connection.buffer_until(b)
    else _Unreachable()
    end

  fun ref _record_send(r: (SendToken | SendError)) =>
    match r
    | let t: SendToken => _returned.push(t.id)
    | let _: SendError => _h.fail("send() returned an error while flooding")
    end

  fun ref _large(): Array[U8] val =>
    recover val Array[U8].init('x', 256_000) end

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    if _started then return KeepReading end
    _started = true
    _tcp_connection.set_so_sndbuf(16384)
    _record_send(_tcp_connection.send("t1"))
    _record_send(_tcp_connection.send("t2"))
    _record_send(_tcp_connection.send("t3"))
    _record_send(_tcp_connection.send(_large()))
    KeepReading

  fun ref _on_throttled() =>
    if not _unmuted_client then
      _unmuted_client = true
      _listener.unmute_client()
    end

  fun ref _on_unthrottled() =>
    if not _resumed then
      _resumed = true
      // Token 4 (256 KiB) is still pending here; this second large send
      // (token 5) appends. Both are pending when we drop the connection.
      _record_send(_tcp_connection.send(_large()))
      _tcp_connection.hard_close()
    end

  fun ref _on_closed() =>
    _closed = true

  fun ref _on_sent(token: SendToken) =>
    _sent_ids.push(token.id)
    _maybe_finish()

  fun ref _on_send_failed(token: SendToken) =>
    _h.assert_true(_closed, "_on_send_failed must arrive after _on_closed")
    _failed_ids.push(token.id)
    _maybe_finish()

  fun ref _maybe_finish() =>
    if (_sent_ids.size() + _failed_ids.size()) != _total_sends then
      return
    end

    // Every returned token gets exactly one terminal callback: not both,
    // not neither.
    for id in _returned.values() do
      var count: USize = 0
      for s in _sent_ids.values() do
        if s == id then count = count + 1 end
      end
      for f in _failed_ids.values() do
        if f == id then count = count + 1 end
      end
      _h.assert_eq[USize](1, count,
        "each token must fire exactly one terminal callback")
    end

    // Both undelivered sends must fail (not just the last one).
    _h.assert_true(_failed_ids.size() >= 2,
      "every accepted-but-undelivered send must fire _on_send_failed")

    // Clean prefix/suffix: all _on_sent ids precede all _on_send_failed ids.
    var max_sent: USize = 0
    for s in _sent_ids.values() do
      if s > max_sent then max_sent = s end
    end
    var min_failed: USize = USize.max_value()
    for f in _failed_ids.values() do
      if f < min_failed then min_failed = f end
    end
    _h.assert_true(max_sent < min_failed,
      "_on_sent ids must all precede _on_send_failed ids")

    // _on_send_failed must also fire in send order (ascending token id).
    var prev_failed: USize = 0
    for f in _failed_ids.values() do
      _h.assert_true(f > prev_failed,
        "_on_send_failed must fire in ascending (send) order")
      prev_failed = f
    end

    _h.complete(true)

class \nodoc\ iso _TestSendSSLPerTokenCompletion is UnitTest
  """
  Overlapping SSL sends each get exactly one `_on_sent`, in send order.

  The SSL analogue of `SendPerTokenCompletion`. An SSL send's completion
  offset is captured after its ciphertext is enqueued, so this checks the
  per-token FIFO fires correctly when several encrypted sends are queued at
  once. The client mutes with a tiny SO_RCVBUF so the sender's pipe fills.
  The server (sender) makes three tiny sends that drain immediately (tokens
  1-3 -> `_on_sent`), then a 256 KiB send whose ciphertext partial-writes and
  stays pending (token 4). When the pipe drains enough to unthrottle, the
  server makes a second 256 KiB send from `_on_unthrottled` (token 5), so
  tokens 4 and 5 are pending at once. The client then drains everything.

  Asserts every returned token fires `_on_sent` exactly once, in ascending id
  order.

  POSIX only, for the same reason as `SendPerTokenCompletion`.
  """
  fun name(): String => "SendSSLPerTokenCompletion"

  fun apply(h: TestHelper) ? =>
    let port = "7913"
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

    let listener = _TestSendSSLPerTokenListener(port, consume sslctx, h)
    h.dispose_when_done(listener)

    h.long_test(30_000_000_000)

actor \nodoc\ _TestSendSSLPerTokenListener is TCPListenerActor
  let _port: String
  let _sslctx: SSLContext val
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _server: (_TestSendSSLPerTokenServer | None) = None
  var _client: (_TestSendSSLPerTokenClient | None) = None

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

  fun ref _on_accept(fd: U32): _TestSendSSLPerTokenServer =>
    let s = _TestSendSSLPerTokenServer(_sslctx, fd, _h, this)
    _server = s
    s

  fun ref _on_closed() =>
    try (_client as _TestSendSSLPerTokenClient).dispose() end
    try (_server as _TestSendSSLPerTokenServer).dispose() end

  fun ref _on_listening() =>
    _client = _TestSendSSLPerTokenClient(_port, _sslctx, _h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestSendSSLPerTokenListener")

  be unmute_client() =>
    try (_client as _TestSendSSLPerTokenClient).resume_reading() end

actor \nodoc\ _TestSendSSLPerTokenClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(port: String, sslctx: SSLContext val, h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.ssl_client(
      TCPConnectAuth(_h.env.root),
      sslctx,
      "localhost",
      port,
      "",
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _tcp_connection.set_so_rcvbuf(4096)
    _tcp_connection.mute()
    _tcp_connection.send("ready")

  fun ref _on_connection_failure(reason: ConnectionFailureReason) =>
    _h.fail("client connect failed")

  be resume_reading() =>
    _tcp_connection.unmute()

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    None
    KeepReading

actor \nodoc\ _TestSendSSLPerTokenServer
  is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper
  let _listener: _TestSendSSLPerTokenListener
  let _total_sends: USize = 5
  var _started: Bool = false
  var _unmuted_client: Bool = false
  var _resumed: Bool = false
  embed _returned: Array[USize] = _returned.create()
  embed _completed: Array[USize] = _completed.create()
  var _expected_next: USize = 1

  new create(sslctx: SSLContext val, fd: U32, h: TestHelper,
    listener: _TestSendSSLPerTokenListener)
  =>
    _h = h
    _listener = listener
    _tcp_connection = TCPConnection.ssl_server(
      TCPServerAuth(_h.env.root),
      sslctx,
      fd,
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _record_send(r: (SendToken | SendError)) =>
    match r
    | let t: SendToken => _returned.push(t.id)
    | let _: SendError => _h.fail("send() returned an error while flooding")
    end

  fun ref _large(): Array[U8] val =>
    recover val Array[U8].init('x', 256_000) end

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    if _started then return KeepReading end
    _started = true
    _tcp_connection.set_so_sndbuf(16384)
    _record_send(_tcp_connection.send("t1"))
    _record_send(_tcp_connection.send("t2"))
    _record_send(_tcp_connection.send("t3"))
    _record_send(_tcp_connection.send(_large()))
    KeepReading

  fun ref _on_throttled() =>
    if not _unmuted_client then
      _unmuted_client = true
      _listener.unmute_client()
    end

  fun ref _on_unthrottled() =>
    if not _resumed then
      _resumed = true
      _record_send(_tcp_connection.send(_large()))
    end

  fun ref _on_sent(token: SendToken) =>
    _h.assert_eq[USize](_expected_next, token.id,
      "_on_sent fired out of order or with a gap")
    _expected_next = _expected_next + 1
    _completed.push(token.id)
    if _completed.size() == _total_sends then
      _h.assert_eq[USize](_returned.size(), _completed.size(),
        "every returned token must fire _on_sent exactly once")
      _tcp_connection.close()
      _h.complete(true)
    end

  fun ref _on_send_failed(token: SendToken) =>
    _h.fail("no send should fail in the drain scenario")

class \nodoc\ iso _TestSendSSLMidFlightDropBoundary is UnitTest
  """
  The SSL analogue of `SendMidFlightDropBoundary`. On a mid-flight drop of an
  SSL connection, the `_on_sent` / `_on_send_failed` split is still a clean
  boundary: every accepted send fires exactly one of the two, a prefix of
  `_on_sent` followed by a suffix of `_on_send_failed`.

  Same backpressure setup as `SendSSLPerTokenCompletion`: three tiny sends
  drain to `_on_sent` (tokens 1-3), a 256 KiB send stays pending (token 4),
  then a second 256 KiB send from `_on_unthrottled` (token 5) leaves 4 and 5
  pending at once. Instead of draining, the server `hard_close()`s right after
  the second send.

  Asserts each of the five tokens fires exactly one terminal callback, that
  both pending sends (4 and 5) fire `_on_send_failed`, that
  `max(_on_sent id) < min(_on_send_failed id)`, and that `_on_send_failed`
  arrives after `_on_closed`.

  POSIX only, for the same reason as `SendMidFlightDropBoundary`.
  """
  fun name(): String => "SendSSLMidFlightDropBoundary"

  fun apply(h: TestHelper) ? =>
    let port = "7914"
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

    let listener = _TestSendSSLMidFlightDropListener(port, consume sslctx, h)
    h.dispose_when_done(listener)

    h.long_test(30_000_000_000)

actor \nodoc\ _TestSendSSLMidFlightDropListener is TCPListenerActor
  let _port: String
  let _sslctx: SSLContext val
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _server: (_TestSendSSLMidFlightDropServer | None) = None
  var _client: (_TestSendSSLMidFlightDropClient | None) = None

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

  fun ref _on_accept(fd: U32): _TestSendSSLMidFlightDropServer =>
    let s = _TestSendSSLMidFlightDropServer(_sslctx, fd, _h, this)
    _server = s
    s

  fun ref _on_closed() =>
    try (_client as _TestSendSSLMidFlightDropClient).dispose() end
    try (_server as _TestSendSSLMidFlightDropServer).dispose() end

  fun ref _on_listening() =>
    _client = _TestSendSSLMidFlightDropClient(_port, _sslctx, _h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestSendSSLMidFlightDropListener")

  be unmute_client() =>
    try (_client as _TestSendSSLMidFlightDropClient).resume_reading() end

actor \nodoc\ _TestSendSSLMidFlightDropClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(port: String, sslctx: SSLContext val, h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.ssl_client(
      TCPConnectAuth(_h.env.root),
      sslctx,
      "localhost",
      port,
      "",
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _tcp_connection.set_so_rcvbuf(4096)
    _tcp_connection.mute()
    _tcp_connection.send("ready")

  fun ref _on_connection_failure(reason: ConnectionFailureReason) =>
    _h.fail("client connect failed")

  be resume_reading() =>
    _tcp_connection.unmute()

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    None
    KeepReading

actor \nodoc\ _TestSendSSLMidFlightDropServer
  is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper
  let _listener: _TestSendSSLMidFlightDropListener
  let _total_sends: USize = 5
  var _started: Bool = false
  var _unmuted_client: Bool = false
  var _resumed: Bool = false
  var _closed: Bool = false
  embed _returned: Array[USize] = _returned.create()
  embed _sent_ids: Array[USize] = _sent_ids.create()
  embed _failed_ids: Array[USize] = _failed_ids.create()

  new create(sslctx: SSLContext val, fd: U32, h: TestHelper,
    listener: _TestSendSSLMidFlightDropListener)
  =>
    _h = h
    _listener = listener
    _tcp_connection = TCPConnection.ssl_server(
      TCPServerAuth(_h.env.root),
      sslctx,
      fd,
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _record_send(r: (SendToken | SendError)) =>
    match r
    | let t: SendToken => _returned.push(t.id)
    | let _: SendError => _h.fail("send() returned an error while flooding")
    end

  fun ref _large(): Array[U8] val =>
    recover val Array[U8].init('x', 256_000) end

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    if _started then return KeepReading end
    _started = true
    _tcp_connection.set_so_sndbuf(16384)
    _record_send(_tcp_connection.send("t1"))
    _record_send(_tcp_connection.send("t2"))
    _record_send(_tcp_connection.send("t3"))
    _record_send(_tcp_connection.send(_large()))
    KeepReading

  fun ref _on_throttled() =>
    if not _unmuted_client then
      _unmuted_client = true
      _listener.unmute_client()
    end

  fun ref _on_unthrottled() =>
    if not _resumed then
      _resumed = true
      _record_send(_tcp_connection.send(_large()))
      _tcp_connection.hard_close()
    end

  fun ref _on_closed() =>
    _closed = true

  fun ref _on_sent(token: SendToken) =>
    _sent_ids.push(token.id)
    _maybe_finish()

  fun ref _on_send_failed(token: SendToken) =>
    _h.assert_true(_closed, "_on_send_failed must arrive after _on_closed")
    _failed_ids.push(token.id)
    _maybe_finish()

  fun ref _maybe_finish() =>
    if (_sent_ids.size() + _failed_ids.size()) != _total_sends then
      return
    end

    // Every returned token gets exactly one terminal callback: not both,
    // not neither.
    for id in _returned.values() do
      var count: USize = 0
      for s in _sent_ids.values() do
        if s == id then count = count + 1 end
      end
      for f in _failed_ids.values() do
        if f == id then count = count + 1 end
      end
      _h.assert_eq[USize](1, count,
        "each token must fire exactly one terminal callback")
    end

    // Both undelivered sends must fail (not just the last one).
    _h.assert_true(_failed_ids.size() >= 2,
      "every accepted-but-undelivered send must fire _on_send_failed")

    // Clean prefix/suffix: all _on_sent ids precede all _on_send_failed ids.
    var max_sent: USize = 0
    for s in _sent_ids.values() do
      if s > max_sent then max_sent = s end
    end
    var min_failed: USize = USize.max_value()
    for f in _failed_ids.values() do
      if f < min_failed then min_failed = f end
    end
    _h.assert_true(max_sent < min_failed,
      "_on_sent ids must all precede _on_send_failed ids")

    // _on_send_failed must also fire in send order (ascending token id).
    var prev_failed: USize = 0
    for f in _failed_ids.values() do
      _h.assert_true(f > prev_failed,
        "_on_send_failed must fire in ascending (send) order")
      prev_failed = f
    end

    _h.complete(true)

class \nodoc\ iso _TestSendGracefulCloseWithPending is UnitTest
  """
  A graceful close() with sends still queued under backpressure flushes those
  queued writes to the peer before shutting down, rather than dropping them.

  Same backpressure setup as SendMidFlightDropBoundary: three tiny sends drain
  to `_on_sent` (tokens 1-3), a 256 KiB send stays queued (token 4), then a
  second 256 KiB send from `_on_unthrottled` (token 5) leaves data queued when
  the server calls close(). Because close() is graceful, every queued byte is
  written before FIN: all five tokens fire `_on_sent` (none fire
  `_on_send_failed`), the client receives every byte the server sent, and
  `_on_closed` fires.

  Without the flush, close() shuts the write side immediately, token 5's bytes
  fail via `_on_send_failed`, and the client never receives them -- the bug in
  issue #304.

  The three completion signals fire at different times -- the fifth `_on_sent`
  lands as the queue drains, before the server's `_on_closed` (which waits on
  the peer's FIN) -- so each is its own expected action rather than one joint
  check.

  POSIX only, for the same reason as `SendPerTokenCompletion`.
  """
  fun name(): String => "SendGracefulCloseWithPending"

  fun ref apply(h: TestHelper) =>
    h.expect_action("server delivered all pending")
    h.expect_action("server closed")
    h.expect_action("client received all bytes")

    let listener = _TestSendGracefulCloseListener(h)
    h.dispose_when_done(listener)
    h.long_test(30_000_000_000)

actor \nodoc\ _TestSendGracefulCloseListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _server: (_TestSendGracefulCloseServer | None) = None
  var _client: (_TestSendGracefulCloseClient | None) = None

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(_h.env.root),
      ifdef linux then "127.0.0.2" else "localhost" end,
      "7915",
      this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestSendGracefulCloseServer =>
    let s = _TestSendGracefulCloseServer(fd, _h, this)
    _server = s
    s

  fun ref _on_listen_failure() =>
    _h.fail("listener failed to start")

  fun ref _on_listening() =>
    _client = _TestSendGracefulCloseClient(_h)

  fun ref _on_closed() =>
    try (_client as _TestSendGracefulCloseClient).dispose() end
    try (_server as _TestSendGracefulCloseServer).dispose() end

  be unmute_client() =>
    try (_client as _TestSendGracefulCloseClient).resume_reading() end

actor \nodoc\ _TestSendGracefulCloseClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper
  // t1+t2+t3 (2+2+2) plus two 256 KiB payloads = every byte the server sends.
  let _expected: USize = 6 + 256_000 + 256_000
  var _total_received: USize = 0
  var _signalled: Bool = false

  new create(h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.client(
      TCPConnectAuth(_h.env.root),
      ifdef linux then "127.0.0.2" else "localhost" end,
      "7915",
      "",
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _tcp_connection.set_so_rcvbuf(4096)
    _tcp_connection.mute()
    _tcp_connection.send("ready")

  fun ref _on_connection_failure(reason: ConnectionFailureReason) =>
    _h.fail("client connect failed")

  be resume_reading() =>
    _tcp_connection.unmute()

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    _total_received = _total_received + data.size()
    if (not _signalled) and (_total_received >= _expected) then
      _signalled = true
      _h.complete_action("client received all bytes")
    end
    KeepReading

actor \nodoc\ _TestSendGracefulCloseServer
  is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper
  let _listener: _TestSendGracefulCloseListener
  let _total_sends: USize = 5
  var _started: Bool = false
  var _unmuted_client: Bool = false
  var _resumed: Bool = false
  embed _returned: Array[USize] = _returned.create()
  embed _sent_ids: Array[USize] = _sent_ids.create()

  new create(fd: U32, h: TestHelper,
    listener: _TestSendGracefulCloseListener)
  =>
    _h = h
    _listener = listener
    _tcp_connection = TCPConnection.server(
      TCPServerAuth(_h.env.root),
      fd,
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_started() =>
    match MakeBufferSize(5)
    | let b: BufferSize => _tcp_connection.buffer_until(b)
    else _Unreachable()
    end

  fun ref _record_send(r: (SendToken | SendError)) =>
    match r
    | let t: SendToken => _returned.push(t.id)
    | let _: SendError => _h.fail("send() returned an error while flooding")
    end

  fun ref _large(): Array[U8] val =>
    recover val Array[U8].init('x', 256_000) end

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    if _started then return KeepReading end
    _started = true
    _tcp_connection.set_so_sndbuf(16384)
    _record_send(_tcp_connection.send("t1"))
    _record_send(_tcp_connection.send("t2"))
    _record_send(_tcp_connection.send("t3"))
    _record_send(_tcp_connection.send(_large()))
    KeepReading

  fun ref _on_throttled() =>
    if not _unmuted_client then
      _unmuted_client = true
      _listener.unmute_client()
    end

  fun ref _on_unthrottled() =>
    if not _resumed then
      _resumed = true
      // Token 5's bytes are queued when we close. A graceful close must flush
      // them, not drop them.
      _record_send(_tcp_connection.send(_large()))
      _tcp_connection.close()
    end

  fun ref _on_closed() =>
    _h.complete_action("server closed")

  fun ref _on_sent(token: SendToken) =>
    _sent_ids.push(token.id)
    if _sent_ids.size() == _total_sends then
      // Every returned token fired _on_sent exactly once; none failed.
      for id in _returned.values() do
        var count: USize = 0
        for s in _sent_ids.values() do
          if s == id then count = count + 1 end
        end
        _h.assert_eq[USize](1, count,
          "each token must fire _on_sent exactly once")
      end
      _h.complete_action("server delivered all pending")
    end

  fun ref _on_send_failed(token: SendToken) =>
    _h.fail("graceful close must flush queued writes, not fail them")

class \nodoc\ iso _TestSendSSLGracefulCloseWithPending is UnitTest
  """
  The SSL analogue of `SendGracefulCloseWithPending`. A graceful close() on an
  SSL connection with sends still queued under backpressure flushes those
  queued writes (ciphertext) to the peer before shutting down.

  Same backpressure setup as `SendSSLMidFlightDropBoundary`: three tiny sends
  drain to `_on_sent` (tokens 1-3), a 256 KiB send stays queued (token 4), then
  a second 256 KiB send from `_on_unthrottled` (token 5) leaves ciphertext
  queued when the server calls close(). Because close() is graceful, every
  queued byte is written before FIN: all five tokens fire `_on_sent` (none fire
  `_on_send_failed`), the client decrypts every byte the server sent, and
  `_on_closed` fires. The SSL path is not a relabel of the plaintext one: the
  queued bytes are ciphertext, and the `_Closing` drain runs `_ssl_flush_sends`,
  which can enqueue more ciphertext and re-defer the FIN.

  POSIX only, for the same reason as `SendSSLPerTokenCompletion`.
  """
  fun name(): String => "SendSSLGracefulCloseWithPending"

  fun apply(h: TestHelper) ? =>
    let port = "7916"
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

    h.expect_action("server delivered all pending")
    h.expect_action("server closed")
    h.expect_action("client received all bytes")

    let listener = _TestSendSSLGracefulCloseListener(port, consume sslctx, h)
    h.dispose_when_done(listener)

    h.long_test(30_000_000_000)

actor \nodoc\ _TestSendSSLGracefulCloseListener is TCPListenerActor
  let _port: String
  let _sslctx: SSLContext val
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _server: (_TestSendSSLGracefulCloseServer | None) = None
  var _client: (_TestSendSSLGracefulCloseClient | None) = None

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

  fun ref _on_accept(fd: U32): _TestSendSSLGracefulCloseServer =>
    let s = _TestSendSSLGracefulCloseServer(_sslctx, fd, _h, this)
    _server = s
    s

  fun ref _on_closed() =>
    try (_client as _TestSendSSLGracefulCloseClient).dispose() end
    try (_server as _TestSendSSLGracefulCloseServer).dispose() end

  fun ref _on_listening() =>
    _client = _TestSendSSLGracefulCloseClient(_port, _sslctx, _h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestSendSSLGracefulCloseListener")

  be unmute_client() =>
    try (_client as _TestSendSSLGracefulCloseClient).resume_reading() end

actor \nodoc\ _TestSendSSLGracefulCloseClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper
  // t1+t2+t3 (2+2+2) plus two 256 KiB payloads = every byte the server sends.
  let _expected: USize = 6 + 256_000 + 256_000
  var _total_received: USize = 0
  var _signalled: Bool = false

  new create(port: String, sslctx: SSLContext val, h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.ssl_client(
      TCPConnectAuth(_h.env.root),
      sslctx,
      "localhost",
      port,
      "",
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _tcp_connection.set_so_rcvbuf(4096)
    _tcp_connection.mute()
    _tcp_connection.send("ready")

  fun ref _on_connection_failure(reason: ConnectionFailureReason) =>
    _h.fail("client connect failed")

  be resume_reading() =>
    _tcp_connection.unmute()

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    _total_received = _total_received + data.size()
    if (not _signalled) and (_total_received >= _expected) then
      _signalled = true
      _h.complete_action("client received all bytes")
    end
    KeepReading

actor \nodoc\ _TestSendSSLGracefulCloseServer
  is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper
  let _listener: _TestSendSSLGracefulCloseListener
  let _total_sends: USize = 5
  var _started: Bool = false
  var _unmuted_client: Bool = false
  var _resumed: Bool = false
  embed _returned: Array[USize] = _returned.create()
  embed _sent_ids: Array[USize] = _sent_ids.create()

  new create(sslctx: SSLContext val, fd: U32, h: TestHelper,
    listener: _TestSendSSLGracefulCloseListener)
  =>
    _h = h
    _listener = listener
    _tcp_connection = TCPConnection.ssl_server(
      TCPServerAuth(_h.env.root),
      sslctx,
      fd,
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _record_send(r: (SendToken | SendError)) =>
    match r
    | let t: SendToken => _returned.push(t.id)
    | let _: SendError => _h.fail("send() returned an error while flooding")
    end

  fun ref _large(): Array[U8] val =>
    recover val Array[U8].init('x', 256_000) end

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    if _started then return KeepReading end
    _started = true
    _tcp_connection.set_so_sndbuf(16384)
    _record_send(_tcp_connection.send("t1"))
    _record_send(_tcp_connection.send("t2"))
    _record_send(_tcp_connection.send("t3"))
    _record_send(_tcp_connection.send(_large()))
    KeepReading

  fun ref _on_throttled() =>
    if not _unmuted_client then
      _unmuted_client = true
      _listener.unmute_client()
    end

  fun ref _on_unthrottled() =>
    if not _resumed then
      _resumed = true
      // Token 5's ciphertext is queued when we close. A graceful close must
      // flush it, not drop it.
      _record_send(_tcp_connection.send(_large()))
      _tcp_connection.close()
    end

  fun ref _on_closed() =>
    _h.complete_action("server closed")

  fun ref _on_sent(token: SendToken) =>
    _sent_ids.push(token.id)
    if _sent_ids.size() == _total_sends then
      for id in _returned.values() do
        var count: USize = 0
        for s in _sent_ids.values() do
          if s == id then count = count + 1 end
        end
        _h.assert_eq[USize](1, count,
          "each token must fire _on_sent exactly once")
      end
      _h.complete_action("server delivered all pending")
    end

  fun ref _on_send_failed(token: SendToken) =>
    _h.fail("graceful close must flush queued writes, not fail them")

class \nodoc\ iso _TestSendCloseFromThrottled is UnitTest
  """
  A `send()` writes to the socket before it returns. A partial write applies
  backpressure and runs `_on_throttled` right there, inside the `send()` call,
  so an application that closes from `_on_throttled` closes the connection from
  inside a `send()` that has already put bytes on the wire.

  That send is accepted: `send()` returns a token, and because a graceful close
  flushes what is queued, the token fires `_on_sent` once `_Closing` drains.

  The close lands in the middle of `_do_send`, after it has queued the bytes. A
  `_do_send` that only recorded the send once the flush was over would find the
  connection closing by then and report the send rejected -- while every byte of
  the payload still reached the peer, unreported.

  The server unmutes the client from `_on_throttled`. Without that the client
  never reads, the drain never finishes, and the test times out rather than
  asserting anything.

  POSIX only, for the same reason as `SendPerTokenCompletion`.
  """
  fun name(): String => "SendCloseFromThrottled"

  fun ref apply(h: TestHelper) =>
    h.expect_action("send accepted")
    h.expect_action("token sent")
    h.expect_action("client received all bytes")

    let listener = _TestSendCloseFromThrottledListener(h)
    h.dispose_when_done(listener)
    h.long_test(30_000_000_000)

actor \nodoc\ _TestSendCloseFromThrottledListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _server: (_TestSendCloseFromThrottledServer | None) = None
  var _client: (_TestSendCloseFromThrottledClient | None) = None

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(_h.env.root),
      ifdef linux then "127.0.0.2" else "localhost" end,
      "9781",
      this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestSendCloseFromThrottledServer =>
    let s = _TestSendCloseFromThrottledServer(fd, _h, this)
    _server = s
    s

  fun ref _on_listen_failure() =>
    _h.fail("listener failed to start")

  fun ref _on_listening() =>
    _client = _TestSendCloseFromThrottledClient(_h)

  fun ref _on_closed() =>
    try (_client as _TestSendCloseFromThrottledClient).dispose() end
    try (_server as _TestSendCloseFromThrottledServer).dispose() end

  be unmute_client() =>
    try (_client as _TestSendCloseFromThrottledClient).resume_reading() end

actor \nodoc\ _TestSendCloseFromThrottledClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper
  let _expected: USize = 256_000
  var _total_received: USize = 0
  var _signalled: Bool = false

  new create(h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.client(
      TCPConnectAuth(_h.env.root),
      ifdef linux then "127.0.0.2" else "localhost" end,
      "9781",
      "",
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _tcp_connection.set_so_rcvbuf(4096)
    _tcp_connection.mute()
    _tcp_connection.send("ready")

  fun ref _on_connection_failure(reason: ConnectionFailureReason) =>
    _h.fail("client connect failed")

  be resume_reading() =>
    _tcp_connection.unmute()

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    _total_received = _total_received + data.size()
    if (not _signalled) and (_total_received >= _expected) then
      _signalled = true
      _h.complete_action("client received all bytes")
    end
    KeepReading

actor \nodoc\ _TestSendCloseFromThrottledServer
  is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper
  let _listener: _TestSendCloseFromThrottledListener
  var _started: Bool = false
  var _unmuted_client: Bool = false
  var _token: (SendToken | None) = None

  new create(fd: U32, h: TestHelper,
    listener: _TestSendCloseFromThrottledListener)
  =>
    _h = h
    _listener = listener
    _tcp_connection = TCPConnection.server(
      TCPServerAuth(_h.env.root),
      fd,
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_started() =>
    match MakeBufferSize(5)
    | let b: BufferSize => _tcp_connection.buffer_until(b)
    else _Unreachable()
    end

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    if _started then return KeepReading end
    _started = true
    _tcp_connection.set_so_sndbuf(16384)
    let payload = recover val Array[U8].init('x', 256_000) end
    match _tcp_connection.send(payload)
    | let t: SendToken =>
      _token = t
      _h.complete_action("send accepted")
    | let _: SendError =>
      _h.fail("send() must be accepted: its bytes reach the peer")
    end
    KeepReading

  fun ref _on_throttled() =>
    if not _unmuted_client then
      _unmuted_client = true
      _listener.unmute_client()
    end
    _tcp_connection.close()

  fun ref _on_sent(token: SendToken) =>
    match _token
    | let t: SendToken if token == t =>
      _h.complete_action("token sent")
    else
      _h.fail("_on_sent fired with an unexpected token")
    end

  fun ref _on_send_failed(token: SendToken) =>
    _h.fail("a graceful close flushes queued writes, so this send must not " +
      "fail")

class \nodoc\ iso _TestSendHardCloseFromThrottled is UnitTest
  """
  The hard-close twin of `SendCloseFromThrottled`.

  `_on_throttled` runs inside the `send()` that hit backpressure, on a
  connection whose first partial write has already put a prefix of the payload
  on the wire. Here the application calls `hard_close()`, which drops the queued
  remainder. The send is still accepted -- `send()` returns a token -- and the
  token fires `_on_send_failed`, because the send never finished reaching the
  OS. An application told the send was rejected outright would retry it on a new
  connection, and the peer that already got the prefix would see it twice.

  This is the negative case, and it is why `SendCloseFromThrottled` is not
  enough on its own. That test asserts a token comes back and reaches
  `_on_sent`, which a `_do_send` that reported every send as delivered would
  satisfy too. This one drives the same setup to the opposite outcome, so a
  `_do_send` that mints a token without tracking whether its bytes reached the
  OS fails one of the two.

  POSIX only, for the same reason as `SendPerTokenCompletion`.
  """
  fun name(): String => "SendHardCloseFromThrottled"

  fun ref apply(h: TestHelper) =>
    h.expect_action("send accepted")
    h.expect_action("token failed")
    h.expect_action("server closed")

    let listener = _TestSendHardCloseFromThrottledListener(h)
    h.dispose_when_done(listener)
    h.long_test(30_000_000_000)

actor \nodoc\ _TestSendHardCloseFromThrottledListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _server: (_TestSendHardCloseFromThrottledServer | None) = None
  var _client: (_TestSendHardCloseFromThrottledClient | None) = None

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(_h.env.root),
      ifdef linux then "127.0.0.2" else "localhost" end,
      "9782",
      this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestSendHardCloseFromThrottledServer =>
    let s = _TestSendHardCloseFromThrottledServer(fd, _h)
    _server = s
    s

  fun ref _on_listen_failure() =>
    _h.fail("listener failed to start")

  fun ref _on_listening() =>
    _client = _TestSendHardCloseFromThrottledClient(_h)

  fun ref _on_closed() =>
    try (_client as _TestSendHardCloseFromThrottledClient).dispose() end
    try (_server as _TestSendHardCloseFromThrottledServer).dispose() end

actor \nodoc\ _TestSendHardCloseFromThrottledClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.client(
      TCPConnectAuth(_h.env.root),
      ifdef linux then "127.0.0.2" else "localhost" end,
      "9782",
      "",
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _tcp_connection.set_so_rcvbuf(4096)
    _tcp_connection.mute()
    _tcp_connection.send("ready")

  fun ref _on_connection_failure(reason: ConnectionFailureReason) =>
    _h.fail("client connect failed")

actor \nodoc\ _TestSendHardCloseFromThrottledServer
  is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper
  var _started: Bool = false
  var _closed: Bool = false
  var _token: (SendToken | None) = None

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
    match MakeBufferSize(5)
    | let b: BufferSize => _tcp_connection.buffer_until(b)
    else _Unreachable()
    end

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    if _started then return KeepReading end
    _started = true
    _tcp_connection.set_so_sndbuf(16384)
    let payload = recover val Array[U8].init('x', 256_000) end
    match _tcp_connection.send(payload)
    | let t: SendToken =>
      _token = t
      // hard_close() fired _on_closed synchronously from inside this send().
      _h.assert_true(_closed,
        "_on_closed must fire before send() hands back the token")
      _h.complete_action("send accepted")
    | let _: SendError =>
      _h.fail("send() must be accepted: a prefix of its bytes reaches the peer")
    end
    KeepReading

  fun ref _on_throttled() =>
    _tcp_connection.hard_close()

  fun ref _on_closed() =>
    _closed = true
    _h.complete_action("server closed")

  fun ref _on_sent(token: SendToken) =>
    _h.fail("a hard close drops the queued remainder, so this send must not " +
      "report as sent")

  fun ref _on_send_failed(token: SendToken) =>
    match _token
    | let t: SendToken if token == t =>
      _h.complete_action("token failed")
    else
      _h.fail("_on_send_failed fired with an unexpected token")
    end

class \nodoc\ iso _TestSendSSLHardCloseFromThrottled is UnitTest
  """
  The SSL analogue of `SendHardCloseFromThrottled`. The application calls
  `hard_close()` from the `_on_throttled` that runs inside its own `send()`.
  `send()` returns a token and the token fires `_on_send_failed`.

  The SSL path is not a relabel of the plaintext one. `_do_send` encrypts the
  payload into the SSL session and enqueues the ciphertext before it mints the
  token, so the token's completion offset is over ciphertext bytes, not the
  application's. This checks that a send accounted in ciphertext still gets its
  one callback when a hard close inside the flush discards the queue.

  POSIX only, for the same reason as `SendSSLPerTokenCompletion`.
  """
  fun name(): String => "SendSSLHardCloseFromThrottled"

  fun apply(h: TestHelper) ? =>
    let port = "9783"
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

    h.expect_action("send accepted")
    h.expect_action("token failed")
    h.expect_action("server closed")

    let listener = _TestSendSSLHardCloseFromThrottledListener(
      port, consume sslctx, h)
    h.dispose_when_done(listener)
    h.long_test(30_000_000_000)

actor \nodoc\ _TestSendSSLHardCloseFromThrottledListener is TCPListenerActor
  let _port: String
  let _sslctx: SSLContext val
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _server: (_TestSendSSLHardCloseFromThrottledServer | None) = None
  var _client: (_TestSendSSLHardCloseFromThrottledClient | None) = None

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

  fun ref _on_accept(fd: U32): _TestSendSSLHardCloseFromThrottledServer =>
    let s = _TestSendSSLHardCloseFromThrottledServer(_sslctx, fd, _h)
    _server = s
    s

  fun ref _on_closed() =>
    try (_client as _TestSendSSLHardCloseFromThrottledClient).dispose() end
    try (_server as _TestSendSSLHardCloseFromThrottledServer).dispose() end

  fun ref _on_listening() =>
    _client = _TestSendSSLHardCloseFromThrottledClient(_port, _sslctx, _h)

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open _TestSendSSLHardCloseFromThrottledListener")

actor \nodoc\ _TestSendSSLHardCloseFromThrottledClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(port: String, sslctx: SSLContext val, h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.ssl_client(
      TCPConnectAuth(_h.env.root),
      sslctx,
      "localhost",
      port,
      "",
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _tcp_connection.set_so_rcvbuf(4096)
    _tcp_connection.mute()
    _tcp_connection.send("ready")

  fun ref _on_connection_failure(reason: ConnectionFailureReason) =>
    _h.fail("client connect failed")

actor \nodoc\ _TestSendSSLHardCloseFromThrottledServer
  is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper
  var _started: Bool = false
  var _closed: Bool = false
  var _token: (SendToken | None) = None

  new create(sslctx: SSLContext val, fd: U32, h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.ssl_server(
      TCPServerAuth(h.env.root),
      sslctx,
      fd,
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_started() =>
    match MakeBufferSize(5)
    | let b: BufferSize => _tcp_connection.buffer_until(b)
    else _Unreachable()
    end

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    if _started then return KeepReading end
    _started = true
    _tcp_connection.set_so_sndbuf(16384)
    let payload = recover val Array[U8].init('x', 256_000) end
    match _tcp_connection.send(payload)
    | let t: SendToken =>
      _token = t
      // hard_close() fired _on_closed synchronously from inside this send().
      _h.assert_true(_closed,
        "_on_closed must fire before send() hands back the token")
      _h.complete_action("send accepted")
    | let _: SendError =>
      _h.fail("send() must be accepted: a prefix of its bytes reaches the peer")
    end
    KeepReading

  fun ref _on_throttled() =>
    _tcp_connection.hard_close()

  fun ref _on_closed() =>
    _closed = true
    _h.complete_action("server closed")

  fun ref _on_sent(token: SendToken) =>
    _h.fail("a hard close drops the queued remainder, so this send must not " +
      "report as sent")

  fun ref _on_send_failed(token: SendToken) =>
    match _token
    | let t: SendToken if token == t =>
      _h.complete_action("token failed")
    else
      _h.fail("_on_send_failed fired with an unexpected token")
    end


class \nodoc\ iso _TestSendDeliveredNotFailedOnHardClose is UnitTest
  """
  A hard close from `_on_throttled` must not report a delivered send as failed.

  `_on_throttled` runs inside the write flush, after a partial `writev` has
  accounted its bytes and before the flush reports the sends those bytes
  completed. A `hard_close()` from the callback fails every send still on the
  queue, so a send the flush had just finished gets `_on_send_failed` even
  though its bytes are gone. An application that believed that would resend
  them, and the peer would see them twice.

  The peer is the oracle. `hard_close()` is a plain `close(2)` and lori sets no
  `SO_LINGER`, so the kernel sends what is in the socket's send buffer before it
  FINs: the peer receives every byte the OS took. Sends complete in order, so a
  send whose last byte sits at cumulative offset N reached the OS once the peer
  holds N bytes, and every such send must have reported `_on_sent`. The client
  counts to its own `_on_closed`; report any earlier and it is still reading
  while bytes arrive, and it undercounts.

  A 256,000-byte send opens a backlog deep enough to keep the connection
  throttled, and twenty-five 32,000-byte sends pile up behind it. Against a
  16 KiB `SO_SNDBUF` a `writev` moves a few tens of kilobytes a pass, so it
  lands mid-send far more often than on a boundary.

  POSIX only, for the same reason as `SendPerTokenCompletion`.
  """
  fun name(): String => "SendDeliveredNotFailedOnHardClose"

  fun ref apply(h: TestHelper) =>
    h.expect_action("split verified")

    let listener = _TestSendDeliveredListener(h)
    h.dispose_when_done(listener)
    h.long_test(30_000_000_000)

actor \nodoc\ _TestSendDeliveredListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _server: (_TestSendDeliveredServer | None) = None
  var _client: (_TestSendDeliveredClient | None) = None

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(_h.env.root),
      ifdef linux then "127.0.0.2" else "localhost" end,
      "9787",
      this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestSendDeliveredServer =>
    let s = _TestSendDeliveredServer(fd, _h, this)
    _server = s
    s

  fun ref _on_listen_failure() =>
    _h.fail("listener failed to start")

  fun ref _on_listening() =>
    _client = _TestSendDeliveredClient(_h, this)

  fun ref _on_closed() =>
    try (_client as _TestSendDeliveredClient).dispose() end
    try (_server as _TestSendDeliveredServer).dispose() end

  be unmute_client() =>
    try (_client as _TestSendDeliveredClient).resume_reading() end

  be client_total(bytes: USize) =>
    try (_server as _TestSendDeliveredServer).peer_received(bytes) end

actor \nodoc\ _TestSendDeliveredClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper
  let _listener: _TestSendDeliveredListener
  var _total_received: USize = 0

  new create(h: TestHelper, listener: _TestSendDeliveredListener) =>
    _h = h
    _listener = listener
    _tcp_connection = TCPConnection.client(
      TCPConnectAuth(_h.env.root),
      ifdef linux then "127.0.0.2" else "localhost" end,
      "9787",
      "",
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _tcp_connection.set_so_rcvbuf(4096)
    _tcp_connection.mute()
    _tcp_connection.send("ready")

  fun ref _on_connection_failure(reason: ConnectionFailureReason) =>
    _h.fail("client connect failed")

  be resume_reading() =>
    _tcp_connection.unmute()

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    _total_received = _total_received + data.size()
    KeepReading

  fun ref _on_closed() =>
    // Report only now. The server's close still flushes its send buffer, so
    // bytes keep arriving after it closes.
    _listener.client_total(_total_received)

actor \nodoc\ _TestSendDeliveredServer
  is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper
  let _listener: _TestSendDeliveredListener
  let _lead: USize = 256_000
  let _chunk: USize = 32_000
  let _total_chunks: USize = 25
  var _started: Bool = false
  var _unmuted_client: Bool = false
  var _queued: USize = 0
  var _reported: Bool = false
  embed _sent_ids: Array[USize] = _sent_ids.create()
  embed _failed_ids: Array[USize] = _failed_ids.create()

  new create(fd: U32, h: TestHelper, listener: _TestSendDeliveredListener) =>
    _h = h
    _listener = listener
    _tcp_connection = TCPConnection.server(
      TCPServerAuth(_h.env.root),
      fd,
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_started() =>
    match MakeBufferSize(5)
    | let b: BufferSize => _tcp_connection.buffer_until(b)
    else _Unreachable()
    end

  fun ref _send_bytes(n: USize) =>
    let payload = recover val Array[U8].init('x', n) end
    match _tcp_connection.send(payload)
    | let _: SendToken =>
      _queued = _queued + 1
    | let _: SendError =>
      _h.fail("send() must be accepted while the connection is writeable")
    end

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    if _started then return KeepReading end
    _started = true
    _tcp_connection.set_so_sndbuf(16384)
    _send_bytes(_lead)
    KeepReading

  fun ref _on_unthrottled() =>
    if _queued <= _total_chunks then
      _send_bytes(_chunk)
    end

  fun ref _on_throttled() =>
    if not _unmuted_client then
      _unmuted_client = true
      _listener.unmute_client()
    end
    if _queued == (_total_chunks + 1) then
      _tcp_connection.hard_close()
    end

  fun ref _on_sent(token: SendToken) =>
    _sent_ids.push(token.id)

  fun ref _on_send_failed(token: SendToken) =>
    _failed_ids.push(token.id)

  be peer_received(bytes: USize) =>
    if _reported then return end
    _reported = true
    // Sends complete in order, so send k finishes at cumulative offset o_k. The
    // peer holding `bytes` means every send with o_k <= bytes reached the OS,
    // and each of those must have reported _on_sent.
    var reached_os: USize = 0
    var offset: USize = 0
    var k: USize = 0
    while k < _queued do
      offset = offset + if k == 0 then _lead else _chunk end
      if offset <= bytes then
        reached_os = reached_os + 1
      end
      k = k + 1
    end
    _h.log("peer=" + bytes.string() + " reached_os=" + reached_os.string()
      + " on_sent=" + _sent_ids.size().string()
      + " on_send_failed=" + _failed_ids.size().string())
    _h.assert_true(_sent_ids.size() >= reached_os,
      "the peer holds " + bytes.string() + " bytes, so " + reached_os.string()
        + " sends reached the OS, but only " + _sent_ids.size().string()
        + " reported _on_sent")
    _h.complete_action("split verified")

  be dispose() =>
    _tcp_connection.hard_close()
