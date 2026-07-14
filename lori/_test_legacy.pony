use "files"
use "pony_test"
use "ssl/net"

// Tests for the Legacy stdlib-net compatibility API (LegacyTCPClient,
// LegacyTCPListener, and their notifiers) built on top of lori.
//
// The integration tests share one listener notifier, `_LegacyTestListenNotify`,
// parameterized by a `_LegacyMode`. The mode builds the test's client and its
// server-side connection notifier, so each test's inputs and assertions live in
// its own mode and notifier classes while the listen/accept plumbing is shared.

primitive \nodoc\ _LegacyTests
  fun tag tests(test: PonyTest) =>
    test(_TestLegacyReadBufferSizeZeroDefaults)
    test(_TestLegacyReadBufferSizePassesThrough)
    test(_TestLegacyMaxSpawnZeroUnlimited)
    test(_TestLegacyMaxSpawnPositive)
    test(_TestLegacyEchoRoundTrip)
    test(_TestLegacyConnectFailed)
    test(_TestLegacySentTransforms)
    test(_TestLegacyWriteFinalBypassesSent)
    test(_TestLegacyExpectFrames)
    test(_TestLegacyExpectErrorsAboveBufferSize)
    test(_TestLegacyExpectInflatingNotifier)
    test(_TestLegacyReceivedTimes)
    test(_TestLegacyProxyVia)
    test(_TestLegacySSLEchoRoundTrip)

// ---------------------------------------------------------------------------
// Mapping primitives (pure, no I/O)
// ---------------------------------------------------------------------------
class \nodoc\ iso _TestLegacyReadBufferSizeZeroDefaults is UnitTest
  """
  A read buffer size of 0 (which lori rejects) falls back to the default,
  since an actor constructor cannot fail.
  """
  fun name(): String => "LegacyReadBufferSizeZeroDefaults"

  fun apply(h: TestHelper) =>
    h.assert_eq[USize](_LegacyReadBufferSize(0)(), DefaultReadBufferSize()())

class \nodoc\ iso _TestLegacyReadBufferSizePassesThrough is UnitTest
  """
  A valid read buffer size is passed through unchanged.
  """
  fun name(): String => "LegacyReadBufferSizePassesThrough"

  fun apply(h: TestHelper) =>
    h.assert_eq[USize](_LegacyReadBufferSize(512)(), 512)
    h.assert_eq[USize](_LegacyReadBufferSize(1)(), 1)

class \nodoc\ iso _TestLegacyMaxSpawnZeroUnlimited is UnitTest
  """
  A connection limit of 0 maps to None (no limit).
  """
  fun name(): String => "LegacyMaxSpawnZeroUnlimited"

  fun apply(h: TestHelper) =>
    h.assert_true(_LegacyMaxSpawn(0) is None)

class \nodoc\ iso _TestLegacyMaxSpawnPositive is UnitTest
  """
  A positive connection limit maps to a MaxSpawn carrying that value.
  """
  fun name(): String => "LegacyMaxSpawnPositive"

  fun apply(h: TestHelper) =>
    match \exhaustive\ _LegacyMaxSpawn(5)
    | let m: MaxSpawn => h.assert_eq[U32](m(), 5)
    | None => h.fail("expected a MaxSpawn, got None")
    end

// Shared integration harness. The `_LegacyMode` interface is in
// `_legacy_mode.pony`.
class \nodoc\ _LegacyTestListenNotify is LegacyTCPListenNotify
  let _h: TestHelper
  let _port: String
  let _mode: _LegacyMode
  var _client: (LegacyTCPClient | None) = None

  new iso create(h: TestHelper, port: String, mode: _LegacyMode) =>
    _h = h
    _port = port
    _mode = mode

  fun ref listening(listen: LegacyTCPListener ref) =>
    _h.complete_action("server listening")
    _client = _mode.make_client(_h, _port)

  fun ref not_listening(listen: LegacyTCPListener ref) =>
    _h.fail("listener failed to listen")

  fun ref connected(listen: LegacyTCPListener ref)
    : LegacyTCPConnectionNotify iso^
  =>
    _mode.make_server(_h)

  fun ref closed(listen: LegacyTCPListener ref) =>
    match _client
    | let c: LegacyTCPClient => c.dispose()
    end

class \nodoc\ _LegacyEchoServerNotify is LegacyTCPConnectionNotify
  """
  Server side that echoes whatever it receives back to the client.
  """
  new iso create() =>
    None

  fun ref received(
    conn: LegacyTCPConnection ref,
    data: Array[U8] iso,
    times: USize)
    : Bool
  =>
    conn.write(consume data)
    true

  fun ref connect_failed(conn: LegacyTCPConnection ref) =>
    None

class \nodoc\ _LegacyDropServerNotify is LegacyTCPConnectionNotify
  """
  Server side that accepts and reads but does nothing with the data. Used when
  the test's assertions all run on the client side.
  """
  new iso create() =>
    None

  fun ref connect_failed(conn: LegacyTCPConnection ref) =>
    None

// ---------------------------------------------------------------------------
// Echo round trip: listening, connected, accepted, received, write() through
// the LegacyTCPConnection interface handle, end to end.
// ---------------------------------------------------------------------------
class \nodoc\ iso _TestLegacyEchoRoundTrip is UnitTest
  fun name(): String => "LegacyEchoRoundTrip"

  fun apply(h: TestHelper) =>
    h.expect_action("server listening")
    h.expect_action("client connected")
    h.expect_action("client got echo")
    _RunLegacy(h, "8790", _ModeEcho)

primitive \nodoc\ _ModeEcho is _LegacyMode
  fun make_client(h: TestHelper, port: String): LegacyTCPClient =>
    LegacyTCPClient(
      TCPConnectAuth(h.env.root), _EchoClient(h), "localhost", port)

  fun make_server(h: TestHelper): LegacyTCPConnectionNotify iso^ =>
    _LegacyEchoServerNotify

class \nodoc\ _EchoClient is LegacyTCPConnectionNotify
  let _h: TestHelper

  new iso create(h: TestHelper) =>
    _h = h

  fun ref connected(conn: LegacyTCPConnection ref) =>
    _h.complete_action("client connected")
    conn.write("hello")

  fun ref received(
    conn: LegacyTCPConnection ref,
    data: Array[U8] iso,
    times: USize)
    : Bool
  =>
    _h.assert_eq[String]("hello", String.from_array(consume data))
    _h.complete_action("client got echo")
    conn.close()
    true

  fun ref connect_failed(conn: LegacyTCPConnection ref) =>
    _h.fail("client failed to connect")

// ---------------------------------------------------------------------------
// Connect failure: _on_connection_failure translates to connect_failed.
// ---------------------------------------------------------------------------
class \nodoc\ iso _TestLegacyConnectFailed is UnitTest
  fun name(): String => "LegacyConnectFailed"

  fun apply(h: TestHelper) =>
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let client =
      LegacyTCPClient(
        TCPConnectAuth(h.env.root), _ConnectFailedClient(h), host, "3457")
    h.dispose_when_done(client)
    h.long_test(5_000_000_000)

class \nodoc\ _ConnectFailedClient is LegacyTCPConnectionNotify
  let _h: TestHelper

  new iso create(h: TestHelper) =>
    _h = h

  fun ref connected(conn: LegacyTCPConnection ref) =>
    _h.fail("connected on a connection that should have failed")

  fun ref connect_failed(conn: LegacyTCPConnection ref) =>
    _h.complete(true)

// ---------------------------------------------------------------------------
// sent transforms outgoing data: the server receives the transformed bytes.
// ---------------------------------------------------------------------------
class \nodoc\ iso _TestLegacySentTransforms is UnitTest
  fun name(): String => "LegacySentTransforms"

  fun apply(h: TestHelper) =>
    h.expect_action("server listening")
    h.expect_action("server got transformed")
    _RunLegacy(h, "8791", _ModeSentTransform)

primitive \nodoc\ _ModeSentTransform is _LegacyMode
  fun make_client(h: TestHelper, port: String): LegacyTCPClient =>
    LegacyTCPClient(
      TCPConnectAuth(h.env.root), _SentTransformClient, "localhost", port)

  fun make_server(h: TestHelper): LegacyTCPConnectionNotify iso^ =>
    _SentTransformServer(h)

class \nodoc\ _SentTransformClient is LegacyTCPConnectionNotify
  new iso create() =>
    None

  fun ref connected(conn: LegacyTCPConnection ref) =>
    conn.write("ping")

  fun ref sent(conn: LegacyTCPConnection ref, data: ByteSeq): ByteSeq =>
    "PING"

  fun ref connect_failed(conn: LegacyTCPConnection ref) =>
    None

class \nodoc\ _SentTransformServer is LegacyTCPConnectionNotify
  let _h: TestHelper

  new iso create(h: TestHelper) =>
    _h = h

  fun ref received(
    conn: LegacyTCPConnection ref,
    data: Array[U8] iso,
    times: USize)
    : Bool
  =>
    _h.assert_eq[String]("PING", String.from_array(consume data))
    _h.complete_action("server got transformed")
    true

  fun ref connect_failed(conn: LegacyTCPConnection ref) =>
    None

// ---------------------------------------------------------------------------
// write_final bypasses the sent notifier: the server receives the raw bytes.
// ---------------------------------------------------------------------------
class \nodoc\ iso _TestLegacyWriteFinalBypassesSent is UnitTest
  fun name(): String => "LegacyWriteFinalBypassesSent"

  fun apply(h: TestHelper) =>
    h.expect_action("server listening")
    h.expect_action("server got raw")
    _RunLegacy(h, "8792", _ModeWriteFinal)

primitive \nodoc\ _ModeWriteFinal is _LegacyMode
  fun make_client(h: TestHelper, port: String): LegacyTCPClient =>
    LegacyTCPClient(
      TCPConnectAuth(h.env.root), _WriteFinalClient, "localhost", port)

  fun make_server(h: TestHelper): LegacyTCPConnectionNotify iso^ =>
    _WriteFinalServer(h)

class \nodoc\ _WriteFinalClient is LegacyTCPConnectionNotify
  new iso create() =>
    None

  fun ref connected(conn: LegacyTCPConnection ref) =>
    // write_final must not run sent, so the server should see "raw", not "XFORM"
    conn.write_final("raw")

  fun ref sent(conn: LegacyTCPConnection ref, data: ByteSeq): ByteSeq =>
    "XFORM"

  fun ref connect_failed(conn: LegacyTCPConnection ref) =>
    None

class \nodoc\ _WriteFinalServer is LegacyTCPConnectionNotify
  let _h: TestHelper

  new iso create(h: TestHelper) =>
    _h = h

  fun ref received(
    conn: LegacyTCPConnection ref,
    data: Array[U8] iso,
    times: USize)
    : Bool
  =>
    _h.assert_eq[String]("raw", String.from_array(consume data))
    _h.complete_action("server got raw")
    true

  fun ref connect_failed(conn: LegacyTCPConnection ref) =>
    None

// ---------------------------------------------------------------------------
// expect(n) frames received data into exactly n-byte chunks.
// ---------------------------------------------------------------------------
class \nodoc\ iso _TestLegacyExpectFrames is UnitTest
  fun name(): String => "LegacyExpectFrames"

  fun apply(h: TestHelper) =>
    h.expect_action("server listening")
    h.expect_action("frame one")
    h.expect_action("frame two")
    _RunLegacy(h, "8793", _ModeExpectFrames)

primitive \nodoc\ _ModeExpectFrames is _LegacyMode
  fun make_client(h: TestHelper, port: String): LegacyTCPClient =>
    LegacyTCPClient(
      TCPConnectAuth(h.env.root), _ExpectFramesClient, "localhost", port)

  fun make_server(h: TestHelper): LegacyTCPConnectionNotify iso^ =>
    _ExpectFramesServer(h)

class \nodoc\ _ExpectFramesClient is LegacyTCPConnectionNotify
  new iso create() =>
    None

  fun ref connected(conn: LegacyTCPConnection ref) =>
    conn.write("aaaabbbb")

  fun ref connect_failed(conn: LegacyTCPConnection ref) =>
    None

class \nodoc\ _ExpectFramesServer is LegacyTCPConnectionNotify
  let _h: TestHelper
  var _n: USize = 0

  new iso create(h: TestHelper) =>
    _h = h

  fun ref accepted(conn: LegacyTCPConnection ref) =>
    try conn.expect(4)? else _h.fail("expect(4) errored") end

  fun ref received(
    conn: LegacyTCPConnection ref,
    data: Array[U8] iso,
    times: USize)
    : Bool
  =>
    let s = String.from_array(consume data)
    _n = _n + 1
    if _n == 1 then
      _h.assert_eq[String]("aaaa", s)
      _h.complete_action("frame one")
    else
      _h.assert_eq[String]("bbbb", s)
      _h.complete_action("frame two")
    end
    true

  fun ref connect_failed(conn: LegacyTCPConnection ref) =>
    None

// ---------------------------------------------------------------------------
// expect errors when qty exceeds the read buffer size the connection was
// created with.
// ---------------------------------------------------------------------------
class \nodoc\ iso _TestLegacyExpectErrorsAboveBufferSize is UnitTest
  fun name(): String => "LegacyExpectErrorsAboveBufferSize"

  fun apply(h: TestHelper) =>
    h.expect_action("server listening")
    h.expect_action("boundary checked")
    _RunLegacy(h, "8794", _ModeExpectBoundary)

primitive \nodoc\ _ModeExpectBoundary is _LegacyMode
  fun make_client(h: TestHelper, port: String): LegacyTCPClient =>
    LegacyTCPClient(
      TCPConnectAuth(h.env.root), _ExpectBoundaryClient(h), "localhost", port
      where read_buffer_size = 64)

  fun make_server(h: TestHelper): LegacyTCPConnectionNotify iso^ =>
    _LegacyDropServerNotify

class \nodoc\ _ExpectBoundaryClient is LegacyTCPConnectionNotify
  let _h: TestHelper

  new iso create(h: TestHelper) =>
    _h = h

  fun ref connected(conn: LegacyTCPConnection ref) =>
    try conn.expect(64)? else _h.fail("expect(64) should not error") end
    try
      conn.expect(65)?
      _h.fail("expect(65) should have errored")
    else
      _h.complete_action("boundary checked")
    end
    conn.close()

  fun ref connect_failed(conn: LegacyTCPConnection ref) =>
    _h.fail("client failed to connect")

// ---------------------------------------------------------------------------
// A notifier whose expect() returns a quantity above the read buffer size is
// bounded to the buffer size, not grown to fit, and the connection keeps
// working.
// ---------------------------------------------------------------------------
class \nodoc\ iso _TestLegacyExpectInflatingNotifier is UnitTest
  fun name(): String => "LegacyExpectInflatingNotifier"

  fun apply(h: TestHelper) =>
    h.expect_action("server listening")
    h.expect_action("expect survived")
    _RunLegacy(h, "8795", _ModeExpectInflating)

primitive \nodoc\ _ModeExpectInflating is _LegacyMode
  fun make_client(h: TestHelper, port: String): LegacyTCPClient =>
    LegacyTCPClient(
      TCPConnectAuth(h.env.root), _ExpectInflatingClient(h), "localhost", port
      where read_buffer_size = 100)

  fun make_server(h: TestHelper): LegacyTCPConnectionNotify iso^ =>
    _LegacyDropServerNotify

class \nodoc\ _ExpectInflatingClient is LegacyTCPConnectionNotify
  let _h: TestHelper

  new iso create(h: TestHelper) =>
    _h = h

  fun ref connected(conn: LegacyTCPConnection ref) =>
    // qty (50) is within the buffer size, but the notifier inflates it to 200.
    // Reaching this line without a runtime abort is the assertion.
    try conn.expect(50)? else _h.fail("expect(50) should not error") end
    _h.complete_action("expect survived")
    conn.close()

  fun ref expect(conn: LegacyTCPConnection ref, qty: USize): USize =>
    200

  fun ref connect_failed(conn: LegacyTCPConnection ref) =>
    _h.fail("client failed to connect")

// ---------------------------------------------------------------------------
// received's `times` counts calls since the last yield, starting at 1.
// ---------------------------------------------------------------------------
class \nodoc\ iso _TestLegacyReceivedTimes is UnitTest
  fun name(): String => "LegacyReceivedTimes"

  fun apply(h: TestHelper) =>
    h.expect_action("server listening")
    h.expect_action("times ok")
    _RunLegacy(h, "8796", _ModeReceivedTimes)

primitive \nodoc\ _ModeReceivedTimes is _LegacyMode
  fun make_client(h: TestHelper, port: String): LegacyTCPClient =>
    LegacyTCPClient(
      TCPConnectAuth(h.env.root), _ReceivedTimesClient, "localhost", port)

  fun make_server(h: TestHelper): LegacyTCPConnectionNotify iso^ =>
    _ReceivedTimesServer(h)

class \nodoc\ _ReceivedTimesClient is LegacyTCPConnectionNotify
  new iso create() =>
    None

  fun ref connected(conn: LegacyTCPConnection ref) =>
    conn.write("aaaabbbbcccc")

  fun ref connect_failed(conn: LegacyTCPConnection ref) =>
    None

class \nodoc\ _ReceivedTimesServer is LegacyTCPConnectionNotify
  let _h: TestHelper
  var _expected: USize = 1

  new iso create(h: TestHelper) =>
    _h = h

  fun ref accepted(conn: LegacyTCPConnection ref) =>
    try conn.expect(4)? else _h.fail("expect(4) errored") end

  fun ref received(
    conn: LegacyTCPConnection ref,
    data: Array[U8] iso,
    times: USize)
    : Bool
  =>
    _h.assert_eq[USize](_expected, times)
    _expected = _expected + 1
    if times == 3 then
      _h.complete_action("times ok")
    end
    true

  fun ref connect_failed(conn: LegacyTCPConnection ref) =>
    None

// ---------------------------------------------------------------------------
// proxy_via redirects the connection to the returned host/service.
// ---------------------------------------------------------------------------
class \nodoc\ iso _TestLegacyProxyVia is UnitTest
  fun name(): String => "LegacyProxyVia"

  fun apply(h: TestHelper) =>
    h.expect_action("server listening")
    h.expect_action("proxied connect")
    _RunLegacy(h, "8797", _ModeProxyVia)

primitive \nodoc\ _ModeProxyVia is _LegacyMode
  fun make_client(h: TestHelper, port: String): LegacyTCPClient =>
    // Dial a dead endpoint; proxy_via redirects to the live listener.
    let dead = ifdef linux then "127.0.0.2" else "localhost" end
    LegacyTCPClient(
      TCPConnectAuth(h.env.root), _ProxyViaClient(h, port), dead, "3458")

  fun make_server(h: TestHelper): LegacyTCPConnectionNotify iso^ =>
    _LegacyDropServerNotify

class \nodoc\ _ProxyViaClient is LegacyTCPConnectionNotify
  let _h: TestHelper
  let _real_port: String

  new iso create(h: TestHelper, real_port: String) =>
    _h = h
    _real_port = real_port

  fun ref proxy_via(host: String, service: String): (String, String) =>
    ("localhost", _real_port)

  fun ref connected(conn: LegacyTCPConnection ref) =>
    _h.complete_action("proxied connect")
    conn.close()

  fun ref connect_failed(conn: LegacyTCPConnection ref) =>
    _h.fail("proxy_via redirect did not connect")

// ---------------------------------------------------------------------------
// SSL echo round trip: the same echo, but each side wraps its notifier in a
// LegacySSLConnection, so the handshake and record framing run on top of the
// plaintext LegacyTCPConnection.
// ---------------------------------------------------------------------------
class \nodoc\ iso _TestLegacySSLEchoRoundTrip is UnitTest
  fun name(): String => "LegacySSLEchoRoundTrip"

  fun apply(h: TestHelper) ? =>
    h.expect_action("server listening")
    h.expect_action("client connected")
    h.expect_action("client got echo")

    let file_auth = FileAuth(h.env.root)
    let sslctx =
      recover
        SSLContext
          .> set_authority(FilePath(file_auth, "assets/cert.pem"))?
          .> set_cert(
            FilePath(file_auth, "assets/cert.pem"),
            FilePath(file_auth, "assets/key.pem"))?
          .> set_client_verify(false)
          .> set_server_verify(false)
      end

    _RunLegacy(h, "8798", _ModeSSLEcho(consume sslctx))

class \nodoc\ val _ModeSSLEcho is _LegacyMode
  let _ctx: SSLContext val

  new val create(ctx: SSLContext val) =>
    _ctx = ctx

  fun make_client(h: TestHelper, port: String): LegacyTCPClient =>
    try
      LegacyTCPClient(
        TCPConnectAuth(h.env.root),
        LegacySSLConnection(_EchoClient(h), _ctx.client("localhost")?),
        "localhost",
        port)
    else
      h.fail("could not create client SSL session")
      LegacyTCPClient(
        TCPConnectAuth(h.env.root), _EchoClient(h), "localhost", port)
    end

  fun make_server(h: TestHelper): LegacyTCPConnectionNotify iso^ =>
    try
      LegacySSLConnection(_LegacyEchoServerNotify, _ctx.server()?)
    else
      h.fail("could not create server SSL session")
      _LegacyDropServerNotify
    end

// ---------------------------------------------------------------------------
// Shared runner: start a listener with the mode and dispose it when done.
// ---------------------------------------------------------------------------
primitive \nodoc\ _RunLegacy
  fun apply(h: TestHelper, port: String, mode: _LegacyMode) =>
    let listener =
      LegacyTCPListener(
        TCPListenAuth(h.env.root),
        _LegacyTestListenNotify(h, port, mode),
        "localhost",
        port)
    h.dispose_when_done(listener)
    h.long_test(5_000_000_000)
