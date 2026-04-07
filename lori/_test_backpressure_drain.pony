use "pony_test"

class \nodoc\ iso _TestBackpressureDrain is UnitTest
  """
  Verify that a connection remains functional after a large write fully drains
  under backpressure while reads are muted.

  Sequence:
  1. Client connects, sets small SO_RCVBUF, mutes itself, sends "ready"
  2. Server receives "ready", sends a payload large enough to trigger
     backpressure (client is muted with small receive buffer)
  3. Server gets throttled, mutes reads, tells listener
  4. Listener tells client to unmute
  5. Client reads all data, sends "ping"
  6. Server unthrottles, unmutes, receives "ping" — test passes

  Timeout means the server never saw the ping, reproducing the bug from
  issue #276.
  """
  fun name(): String => "BackpressureDrain"

  fun ref apply(h: TestHelper) =>
    h.expect_action("listener listening")
    h.expect_action("server started")
    h.expect_action("client connected")
    h.expect_action("client ready")
    h.expect_action("server throttled")
    h.expect_action("server unthrottled")
    h.expect_action("server received ping")

    let listener = _TestBackpressureDrainListener(h)
    h.dispose_when_done(listener)

    h.long_test(30_000_000_000)

actor \nodoc\ _TestBackpressureDrainListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _server: (_TestBackpressureDrainServer | None) = None
  var _client: (_TestBackpressureDrainClient | None) = None

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(_h.env.root),
      "127.0.0.2",
      "9770",
      this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestBackpressureDrainServer =>
    let s = _TestBackpressureDrainServer(fd, _h, this)
    _server = s
    s

  fun ref _on_listen_failure() =>
    _h.fail("listener failed to start")

  fun ref _on_listening() =>
    _h.complete_action("listener listening")
    _client = _TestBackpressureDrainClient(_h)

  be server_throttled(payload_size: USize) =>
    try
      (_client as _TestBackpressureDrainClient)
        .start_reading(payload_size)
    end

  be dispose() =>
    try (_client as _TestBackpressureDrainClient).dispose() end
    try (_server as _TestBackpressureDrainServer).dispose() end
    _tcp_listener.close()

actor \nodoc\ _TestBackpressureDrainServer
  is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper
  let _listener: _TestBackpressureDrainListener
  var _payload_size: USize = 0

  new create(fd: U32, h: TestHelper,
    listener: _TestBackpressureDrainListener)
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
    _h.complete_action("server started")

  fun ref _on_throttled() =>
    _h.complete_action("server throttled")
    _tcp_connection.mute()
    _listener.server_throttled(_payload_size)

  fun ref _on_unthrottled() =>
    _h.complete_action("server unthrottled")
    _tcp_connection.unmute()

  fun ref _on_received(data: Array[U8] iso) =>
    let received = String.from_array(consume data)
    if received == "ready" then
      // Query effective SO_SNDBUF — Linux doubles the requested value and
      // the default is typically 16KB (effective ~32KB). Send 4x that to
      // reliably overflow both the send and receive buffers.
      (_, let sndbuf: U32) = _tcp_connection.get_so_sndbuf()
      _payload_size = (sndbuf.usize() * 4).max(256_000)
      let payload = recover iso Array[U8].init('x', _payload_size) end
      _tcp_connection.send(consume payload)
    elseif received == "ping" then
      _h.complete_action("server received ping")
      _h.complete(true)
    end

actor \nodoc\ _TestBackpressureDrainClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper
  var _total_received: USize = 0
  var _payload_size: USize = 0

  new create(h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.client(
      TCPConnectAuth(_h.env.root),
      "127.0.0.2",
      "9770",
      "",
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _h.complete_action("client connected")
    // Small receive buffer so the pipe fills quickly
    _tcp_connection.set_so_rcvbuf(4096)
    // Stop reading to create TCP backpressure on the server
    _tcp_connection.mute()
    // Tell the server we're ready (muted with small buffer)
    _tcp_connection.send("ready")
    _h.complete_action("client ready")

  fun ref _on_connection_failure(reason: ConnectionFailureReason) =>
    _h.fail("client connect failed")

  be start_reading(payload_size: USize) =>
    _payload_size = payload_size
    _tcp_connection.unmute()

  fun ref _on_received(data: Array[U8] iso) =>
    _total_received = _total_received + data.size()
    if _total_received >= _payload_size then
      _tcp_connection.send("ping")
    end
