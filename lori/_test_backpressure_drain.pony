use "pony_test"

class \nodoc\ iso _TestBackpressureDrain is UnitTest
  """
  Verify that a connection remains functional after a large write fully drains
  under backpressure while reads are muted.

  Sequence:
  1. Client connects, sets small SO_RCVBUF, mutes itself, sends "ready"
  2. Server receives "ready" (via buffer_until framing), sends a large payload
  3. Server gets throttled, mutes reads, tells listener
  4. Listener tells client to unmute
  5. Client reads all data, sends "ping"
  6. Server unthrottles, unmutes, receives "ping" (via buffer_until) — passes

  Timeout means the server never saw the ping, reproducing the bug from
  issue #276.

  POSIX only. The production drain logic is platform-neutral, but this test
  needs to provoke write backpressure with a fixed-size payload, and Windows
  loopback buffers far more than the requested SO_SNDBUF/SO_RCVBUF (a 16 MB
  send still drains without throttling). Triggering backpressure on Windows
  requires a send-until-throttled loop rather than a fixed payload; the
  stdlib's net/TCPThrottle test uses that pattern.
  """
  fun name(): String => "BackpressureDrain"

  fun ref apply(h: TestHelper) =>
    h.expect_action("listener listening")
    h.expect_action("server started")
    h.expect_action("client connected")
    h.expect_action("client ready")
    h.expect_action("server queued payload")
    h.expect_action("server payload delivered")
    h.expect_action("server throttled")
    h.expect_action("server unthrottled")
    h.expect_action("client receiving data")
    h.expect_action("client sent ping")
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
      ifdef linux then "127.0.0.2" else "localhost" end,
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
  var _got_ready: Bool = false
  var _payload_token: (SendToken | None) = None

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
    // Frame incoming messages: "ready" is 5 bytes
    match MakeBufferSize(5)
    | let b: BufferSize => _tcp_connection.buffer_until(b)
    else _Unreachable()
    end

  fun ref _on_throttled() =>
    _h.complete_action("server throttled")
    _tcp_connection.mute()
    _listener.server_throttled(_payload_size)

  fun ref _on_unthrottled() =>
    _h.complete_action("server unthrottled")
    _tcp_connection.unmute()

  fun ref _on_sent(token: SendToken) =>
    match _payload_token
    | let t: SendToken if token is t =>
      _h.complete_action("server payload delivered")
    end

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    if not _got_ready then
      _got_ready = true
      // Switch framing to expect "ping" (4 bytes)
      match MakeBufferSize(4)
      | let b: BufferSize => _tcp_connection.buffer_until(b)
      else _Unreachable()
      end
      // Shrink the send buffer so the pipe is small and drains quickly.
      // With the client muted and SO_RCVBUF at 4096, we only need to
      // overflow SO_SNDBUF + SO_RCVBUF to trigger backpressure.
      _tcp_connection.set_so_sndbuf(16384)
      _payload_size = 256_000
      let payload = recover iso Array[U8].init('x', _payload_size) end
      match _tcp_connection.send(consume payload)
      | let t: SendToken =>
        _payload_token = t
        _h.complete_action("server queued payload")
      | let _: SendError =>
        _h.fail("server send failed")
      end
    else
      _h.complete_action("server received ping")
      _tcp_connection.close()
      _h.complete(true)
    end
    KeepReading

actor \nodoc\ _TestBackpressureDrainClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper
  var _total_received: USize = 0
  var _payload_size: USize = 0
  var _sent_ping: Bool = false

  new create(h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.client(
      TCPConnectAuth(_h.env.root),
      ifdef linux then "127.0.0.2" else "localhost" end,
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

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    if _total_received == 0 then
      _h.complete_action("client receiving data")
    end
    _total_received = _total_received + data.size()
    _h.log("client received " + _total_received.string() + " of "
      + _payload_size.string())
    if not _sent_ping and (_total_received >= _payload_size) then
      _sent_ping = true
      _h.complete_action("client sent ping")
      _tcp_connection.send("ping")
      _tcp_connection.close()
    end
    KeepReading

class \nodoc\ iso _TestWriteOnlyEventReadRecovery is UnitTest
  """
  Verify that a connection still receives data after a write-only oneshot
  event fully drains its pending writes under backpressure.

  Same shape as BackpressureDrain, but the server sends from outside the read
  path: it never mutes on throttle or unmutes on unthrottle. The fix for issue
  #276 restored read interest via unmute()'s _set_readable() + _read(); a relay
  / proxy / streaming server that never mutes doesn't take that path. When a
  write-only (writeable, no readable) one-shot event drains the last of the
  payload, the whole fd is disarmed and nothing re-arms reads, so the follow-up
  "ping" never reaches _on_received. The write-only re-arm fix is platform-
  neutral (every platform now uses one-shot readiness), but see the note on
  BackpressureDrain for why this test is POSIX only.

  Sequence:
  1. Client connects, sets small SO_RCVBUF, mutes itself, sends "ready"
  2. Server receives "ready", sends a large payload (never mutes)
  3. Server gets throttled, tells the listener (does NOT mute)
  4. Listener tells client to unmute
  5. Client drains all data, sends "ping"
  6. Server receives "ping" — passes

  Timeout means the server went read-deaf, reproducing issue #294.
  """
  fun name(): String => "WriteOnlyEventReadRecovery"

  fun ref apply(h: TestHelper) =>
    h.expect_action("listener listening")
    h.expect_action("server started")
    h.expect_action("client connected")
    h.expect_action("server queued payload")
    h.expect_action("server throttled")
    h.expect_action("client receiving data")
    h.expect_action("client sent ping")
    h.expect_action("server received ping")

    let listener = _TestWriteOnlyEventReadRecoveryListener(h)
    h.dispose_when_done(listener)

    h.long_test(30_000_000_000)

actor \nodoc\ _TestWriteOnlyEventReadRecoveryListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _server: (_TestWriteOnlyEventReadRecoveryServer | None) = None
  var _client: (_TestWriteOnlyEventReadRecoveryClient | None) = None

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(_h.env.root),
      ifdef linux then "127.0.0.2" else "localhost" end,
      "9771",
      this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestWriteOnlyEventReadRecoveryServer =>
    let s = _TestWriteOnlyEventReadRecoveryServer(fd, _h, this)
    _server = s
    s

  fun ref _on_listen_failure() =>
    _h.fail("listener failed to start")

  fun ref _on_listening() =>
    _h.complete_action("listener listening")
    _client = _TestWriteOnlyEventReadRecoveryClient(_h)

  be server_throttled(payload_size: USize) =>
    try
      (_client as _TestWriteOnlyEventReadRecoveryClient)
        .start_reading(payload_size)
    end

  be dispose() =>
    try (_client as _TestWriteOnlyEventReadRecoveryClient).dispose() end
    try (_server as _TestWriteOnlyEventReadRecoveryServer).dispose() end
    _tcp_listener.close()

actor \nodoc\ _TestWriteOnlyEventReadRecoveryServer
  is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper
  let _listener: _TestWriteOnlyEventReadRecoveryListener
  var _payload_size: USize = 0
  var _got_ready: Bool = false

  new create(fd: U32, h: TestHelper,
    listener: _TestWriteOnlyEventReadRecoveryListener)
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
    match MakeBufferSize(5)
    | let b: BufferSize => _tcp_connection.buffer_until(b)
    else _Unreachable()
    end

  fun ref _on_throttled() =>
    // Crucially: do NOT mute. A relay/proxy/streaming server sending from
    // outside the read path keeps reading enabled while it backpressures.
    _h.complete_action("server throttled")
    _listener.server_throttled(_payload_size)

  fun ref _on_unthrottled() =>
    // Crucially: do NOT unmute. unmute() is what re-armed reads after the
    // #276 fix; a server that never muted can't rely on it.
    None

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    if not _got_ready then
      _got_ready = true
      match MakeBufferSize(4)
      | let b: BufferSize => _tcp_connection.buffer_until(b)
      else _Unreachable()
      end
      _tcp_connection.set_so_sndbuf(16384)
      _payload_size = 256_000
      let payload = recover iso Array[U8].init('x', _payload_size) end
      match _tcp_connection.send(consume payload)
      | let _: SendToken =>
        _h.complete_action("server queued payload")
      | let _: SendError =>
        _h.fail("server send failed")
      end
    else
      _h.complete_action("server received ping")
      _tcp_connection.close()
      _h.complete(true)
    end
    KeepReading

actor \nodoc\ _TestWriteOnlyEventReadRecoveryClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper
  var _total_received: USize = 0
  var _payload_size: USize = 0
  var _sent_ping: Bool = false

  new create(h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.client(
      TCPConnectAuth(_h.env.root),
      ifdef linux then "127.0.0.2" else "localhost" end,
      "9771",
      "",
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _h.complete_action("client connected")
    _tcp_connection.set_so_rcvbuf(4096)
    _tcp_connection.mute()
    _tcp_connection.send("ready")

  fun ref _on_connection_failure(reason: ConnectionFailureReason) =>
    _h.fail("client connect failed")

  be start_reading(payload_size: USize) =>
    _payload_size = payload_size
    _tcp_connection.unmute()

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    if _total_received == 0 then
      _h.complete_action("client receiving data")
    end
    _total_received = _total_received + data.size()
    if not _sent_ping and (_total_received >= _payload_size) then
      _sent_ping = true
      _h.complete_action("client sent ping")
      _tcp_connection.send("ping")
    end
    KeepReading

class \nodoc\ iso _TestReadableEventWriteRecovery is UnitTest
  """
  Verify that a connection still drains its writes after a readable one-shot
  event arrives while it is throttled and then mutes.

  The write-side mirror of WriteOnlyEventReadRecovery. On backends where one
  subscription covers the whole fd (Linux epoll, Windows readiness), any event
  disarms it. When backpressure has armed write interest and a readable event
  arrives, the read that mutes must NOT reach _read's EAGAIN resubscribe — that
  resubscribe re-arms every not-ready direction, so it would restore the write
  interest and self-heal. A read that mutes returns at the top of _read's loop,
  before it touches the socket again, so it never reaches EAGAIN. Nothing
  re-arms the write, and the connection wedges.

  Sequence:
  1. Client connects, sets small SO_RCVBUF, mutes itself, sends a 64 KiB frame
  2. Server receives the whole frame (buffer_until), echoes it — the muted
     client can't drain it, so the echo backpressures and throttles the server;
     the server does NOT mute, and its read loop reaches EAGAIN with reads and
     write both armed
  3. Server tells the listener it throttled; listener tells the client to poke
  4. Client sends a poke (still muted) — a fresh readable event at the throttled
     server; it can't echo the first chunk, so it stashes it and mutes, and the
     read returns before its next socket read rather than reaching EAGAIN, so
     the whole-fd write interest stays dropped
  5. Server tells the listener it muted; listener tells the client to drain
  6. Client unmutes and reads; the write re-arm restores the writeable edge, the
     server unthrottles, echoes the poke, and the client sees all bytes back

  Timeout means the server never unthrottled — the write interest stayed
  dropped. POSIX only, for the same reason as BackpressureDrain (Windows
  loopback buffers past SO_SNDBUF/SO_RCVBUF, so a fixed payload won't throttle).
  """
  fun name(): String => "ReadableEventWriteRecovery"

  fun ref apply(h: TestHelper) =>
    h.expect_action("listener listening")
    h.expect_action("server started")
    h.expect_action("client connected")
    h.expect_action("client sent frame")
    h.expect_action("server throttled")
    h.expect_action("client sent poke")
    h.expect_action("server muted after poke")
    h.expect_action("server unthrottled")
    h.expect_action("client received all echoes")

    let listener = _TestReadableEventWriteRecoveryListener(h)
    h.dispose_when_done(listener)

    h.long_test(30_000_000_000)

actor \nodoc\ _TestReadableEventWriteRecoveryListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper
  var _server: (_TestReadableEventWriteRecoveryServer | None) = None
  var _client: (_TestReadableEventWriteRecoveryClient | None) = None

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(_h.env.root),
      ifdef linux then "127.0.0.2" else "localhost" end,
      "9772",
      this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestReadableEventWriteRecoveryServer =>
    let s = _TestReadableEventWriteRecoveryServer(fd, _h, this)
    _server = s
    s

  fun ref _on_listen_failure() =>
    _h.fail("listener failed to start")

  fun ref _on_listening() =>
    _h.complete_action("listener listening")
    _client = _TestReadableEventWriteRecoveryClient(_h)

  be server_throttled() =>
    try
      (_client as _TestReadableEventWriteRecoveryClient).send_poke()
    end

  be server_muted() =>
    try
      (_client as _TestReadableEventWriteRecoveryClient).start_draining()
    end

  be dispose() =>
    try (_client as _TestReadableEventWriteRecoveryClient).dispose() end
    try (_server as _TestReadableEventWriteRecoveryServer).dispose() end
    _tcp_listener.close()

actor \nodoc\ _TestReadableEventWriteRecoveryServer
  is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper
  let _listener: _TestReadableEventWriteRecoveryListener
  var _pending: (Array[U8] iso | None) = None
  var _got_frame: Bool = false
  var _poke_muted: Bool = false

  new create(fd: U32, h: TestHelper,
    listener: _TestReadableEventWriteRecoveryListener)
  =>
    _h = h
    _listener = listener
    // Read buffer large enough to receive the whole frame as one _on_received,
    // so the server does not mute mid-frame.
    let rbs =
      match MakeReadBufferSize(131072)
      | let r: ReadBufferSize => r
      else
        _Unreachable()
        DefaultReadBufferSize()
      end
    _tcp_connection = TCPConnection.server(
      TCPServerAuth(_h.env.root),
      fd,
      this,
      this,
      rbs)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_started() =>
    _h.complete_action("server started")
    // Frame the incoming 64 KiB payload so it arrives as a single _on_received.
    match MakeBufferSize(65536)
    | let b: BufferSize => _tcp_connection.buffer_until(b)
    else _Unreachable()
    end
    // Shrink the send buffer so echoing the frame to a muted client throttles.
    _tcp_connection.set_so_sndbuf(16384)

  fun ref _on_throttled() =>
    _h.complete_action("server throttled")
    _listener.server_throttled()

  fun ref _on_unthrottled() =>
    // Recovery: the writeable edge arrived, so we echo the stashed poke and
    // resume reading. Without the write re-arm fix this never runs.
    _h.complete_action("server unthrottled")
    match _pending = None
    | let d: Array[U8] iso =>
      _tcp_connection.send(consume d)
      _tcp_connection.unmute()
    end

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    if not _got_frame then
      _got_frame = true
      // Stream from here. The read that mutes returns at the top of _read's
      // loop, before it touches the socket again, so it never reaches EAGAIN --
      // which is what leaves the whole-fd write interest dropped.
      _tcp_connection.buffer_until(Streaming)
      // Echo the frame. The muted client can't drain it, so this backpressures
      // and throttles us, but we don't mute — our read loop reaches EAGAIN with
      // reads and write both armed.
      _tcp_connection.send(consume data)
    elseif _tcp_connection.is_writeable() then
      // A later poke chunk, after we've recovered and drained: echo it
      // normally. Stashing here (when writeable, not throttled) would strand it
      // — nothing would fire _on_unthrottled to send it.
      _tcp_connection.send(consume data)
    else
      // The first poke chunk: a fresh readable event while throttled. We can't
      // echo it, so we stash it and mute. The muting read returns before its
      // next socket read, so it never reaches EAGAIN, and on a whole-fd
      // one-shot backend the pending write interest stays dropped.
      // Signal once — later chunks take the writeable branch above.
      _pending = consume data
      _tcp_connection.mute()
      if not _poke_muted then
        _poke_muted = true
        _h.complete_action("server muted after poke")
        _listener.server_muted()
      end
    end
    KeepReading

actor \nodoc\ _TestReadableEventWriteRecoveryClient
  is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper
  var _total_received: USize = 0

  new create(h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.client(
      TCPConnectAuth(_h.env.root),
      ifdef linux then "127.0.0.2" else "localhost" end,
      "9772",
      "",
      this,
      this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _h.complete_action("client connected")
    // Small receive buffer + muted so the server's echo backpressures.
    _tcp_connection.set_so_rcvbuf(4096)
    _tcp_connection.mute()
    let frame = recover iso Array[U8].init('x', 65536) end
    _tcp_connection.send(consume frame)
    _h.complete_action("client sent frame")

  fun ref _on_connection_failure(reason: ConnectionFailureReason) =>
    _h.fail("client connect failed")

  be send_poke() =>
    // Sent while still muted, so it lands at the throttled server as a readable
    // event before any writeable edge (the server's send buffer is still full).
    // Big enough that the server sees it however it fragments; the muting read
    // returns before its next socket read either way, so it never reaches
    // EAGAIN — see the test docstring.
    let poke = recover iso Array[U8].init('y', 524288) end
    _tcp_connection.send(consume poke)
    _h.complete_action("client sent poke")

  be start_draining() =>
    // Only after the server has stashed and muted the poke — so the poke's
    // readable event has already dropped the write interest — do we unmute and
    // let the server's send buffer drain.
    _tcp_connection.unmute()

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    _total_received = _total_received + data.size()
    // 65536 (frame echo) + 524288 (poke echo). Without the write re-arm the
    // server stays throttled, the poke is never echoed, and this never
    // completes.
    if _total_received >= 589824 then
      _h.complete_action("client received all echoes")
      _tcp_connection.close()
      _h.complete(true)
    end
    KeepReading
