"""
Swarm TCP stress engine for lori.

A closed, count-driven TCP workload for stressing lori's TCP stack. Every
behaviour is a CLI flag set by the orchestrator (orchestrate_tcp.py); the engine
draws nothing on its own -- its `_Config` defaults exist only for hand-running. A
fixed number of client connections
is churned through a listener at a bounded concurrency; each client sends a
stamped payload, the server echoes it, and the client verifies the echo
byte-for-byte before closing.

Each swarm dimension is tied to a distinct code path in lori's
`tcp_connection.pony` (see stress-tests/tcp-swarm/README.md):

* `--payload-size` / `--messages` -- how much each connection sends, and in how
  many `send()` calls.
* `--write-shape` (`write` | `writev`) -- a single-buffer `send(ByteSeq)` vs a
  vectored `send(ByteSeqIter)`.
* `--writev-chunks` (N, writev only) -- how many buffers a single vectored
  `send` splits its payload into. Above `PonyTCP.writev_max()` (IOV_MAX on POSIX,
  1 on Windows) lori's `_send_pending_writes()` takes its multi-batch path,
  sending one `writev_max`-sized batch per pass.
* `--expect` (0 = off, N = frame size) -- fixed-size framed reads via
  `buffer_until(MakeBufferSize(N))` vs whole-buffer `Streaming` reads.
* `--close` (`graceful` | `hard`) -- a graceful `close()` (FIN, drains) vs a
  muted `close()`, which lori routes to `hard_close()` (immediate teardown). The
  client closes only after its whole echo is back, so the hard path drops no data
  here -- it exercises the distinct teardown/unsubscribe code.
* `--read-buffer-size` -- the per-connection read buffer size (a `ReadBufferSize`).
* `--yield-after-reading` -- after this many received bytes, the endpoint returns
  `YieldReading` to exit the read loop cooperatively (it resumes next turn). This
  is lori's application-driven yield; there is no byte-threshold read yield in the
  connection itself.
* `--connections` / `--concurrency` -- total connections to churn, and the
  in-flight cap.
* `--host` / `--port` -- where the listener binds (default `localhost` / ephemeral).

Because lori's `send()` is fallible and does not queue on backpressure, both
endpoints handle backpressure explicitly (this is the main way this engine
differs from a `net`-package echo test):

* The client runs a resumable send-pump: it hands the connection one message at a
  time while `is_writeable()`, and resumes from `_on_unthrottled` after
  backpressure clears.
* The echo server, when it cannot echo a chunk, stashes that one chunk and
  `mute()`s; `_on_unthrottled` sends the stash and `unmute()`s. It checks
  `is_writeable()` before `send()` because `send(consume data)` consumes the
  buffer even when it returns an error, so a "try then stash" would lose data.

Oracles:

* Echo integrity -- each connection sends a per-connection pseudo-random byte
  stream (byte at position p is the low 8 bits of a splitmix64 hash of
  (connection-id, p)), and verifies every echoed byte against it. Systematic
  corruption -- a run of wrong bytes, a misrouted chunk, a byte from another
  connection -- is caught near-certainly; because the values are 8-bit, a lone
  single-byte reorder or duplicate aliases with probability ~1/256. A short echo
  is caught by the conservation tally (the connection never reaches its target),
  not the byte check. Every connection must verify: the client closes only after
  it has read its whole echo back.
* Conservation -- every spawned connection reaches a terminal state (closed or
  connect-failed); the engine reports the tally.
* Crash / assert -- debug build, asserts on.

On success (every connection verified) the engine prints its RESULT line and
PASS, then returns, letting the program reach natural quiescence. Anything short
of full verification -- a connect failure, a short echo, or a byte mismatch --
prints FAIL and forces a non-zero exit.
"""
use "../../lori"
use "collections"
use "time"

use @printf[I32](fmt: Pointer[U8] tag, ...)
use @fprintf[I32](stream: Pointer[U8] tag, fmt: Pointer[U8] tag, ...)
use @fflush[I32](stream: Pointer[U8] tag)
use @pony_os_stdout[Pointer[U8]]()
use @pony_os_stderr[Pointer[U8]]()
use @exit[None](status: I32)

primitive _Flags
  """
  Parse `--key value` pairs (and bare `--key` as "true") from the program args.
  The runtime strips its own `--pony*` flags before main, so only workload flags
  arrive here; unknown keys are ignored by _Config.
  """
  fun apply(args: Array[String] box): Map[String, String] val =>
    let out = recover Map[String, String] end
    var i: USize = 1
    while i < args.size() do
      try
        let arg = args(i)?
        if arg.at("--") then
          let key = arg.substring(2)
          if ((i + 1) < args.size()) and (not args(i + 1)?.at("--")) then
            out(consume key) = args(i + 1)?
            i = i + 2
          else
            out(consume key) = "true"
            i = i + 1
          end
        else
          i = i + 1
        end
      else
        i = i + 1
      end
    end
    consume out

class val _Config
  let host: String
  let port: String
  let connections: USize
  let concurrency: USize
  let payload_size: USize
  let messages: USize
  let close_hard: Bool
  let use_writev: Bool
  let writev_chunks: USize
  let expect_frame: USize
  let read_buffer_size: USize
  let yield_after_reading: USize

  new val create(m: Map[String, String] val) =>
    // "localhost", not "127.0.0.1": the literal v4 address makes macOS wall the
    // client at ~16k ephemeral ports mid-run (connections then fail, which this
    // test treats as a failure); "localhost" sidesteps it.
    host = _str(m, "host", "localhost")
    port = _str(m, "port", "0")
    connections = _usize(m, "connections", 1000)
    // Floor concurrency at 1: 0 would spawn nothing yet never finish (a silent
    // hang the watchdog would catch as a false timeout).
    concurrency = _usize(m, "concurrency", 64).max(1)
    payload_size = _usize(m, "payload-size", 64)
    messages = _usize(m, "messages", 1)
    close_hard = _str(m, "close", "graceful") == "hard"
    use_writev = _str(m, "write-shape", "write") == "writev"
    // How many buffers a single vectored `send` splits its payload into. Above
    // `PonyTCP.writev_max()` -- IOV_MAX on POSIX, 1 on Windows -- it drives
    // lori's multi-batch send. Default 4; writev only.
    writev_chunks = _usize(m, "writev-chunks", 4).max(1)
    read_buffer_size = _usize(m, "read-buffer-size", 16384)
    // Clamp expect to the read buffer: buffer_until returns BufferSizeAboveMinimum
    // when the frame exceeds the read-buffer minimum, so clamping here keeps the
    // call from failing (the call sites then assert that with _Unreachable). The
    // orchestrator already draws expect <= read-buffer; this clamp only makes a
    // directly-run engine safe from that one error. NOTE: it does NOT save a
    // directly-run engine from a non-dividing --expect: for framed reads to
    // terminate, payload_size * messages must be a whole number of frames, or the
    // trailing partial frame is never delivered and the client hangs. The
    // orchestrator guarantees divisibility by drawing only power-of-two sizes; a
    // hand-run engine must arrange it itself.
    expect_frame = _usize(m, "expect", 0).min(read_buffer_size)
    yield_after_reading = _usize(m, "yield-after-reading", 16384)

  fun tag _str(m: Map[String, String] val, key: String, default: String)
    : String
  =>
    try m(key)? else default end

  fun tag _usize(m: Map[String, String] val, key: String, default: USize)
    : USize
  =>
    try m(key)?.usize()? else default end

  fun read_buffer(): ReadBufferSize =>
    """
    The read buffer size as a validated `ReadBufferSize`. `read_buffer_size` is
    at least 1 for every orchestrator draw (min drawn value is 128) and for the
    default, so the validation-failure branch is unreachable in practice; a
    hand-run engine passing `--read-buffer-size 0` crashes here rather than
    stalling on a zero-length buffer.
    """
    match MakeReadBufferSize(read_buffer_size)
    | let r: ReadBufferSize => r
    else
      _Unreachable()
      DefaultReadBufferSize()
    end

primitive _Keystream
  """
  The echo oracle checks a per-connection pseudo-random byte stream: the byte at
  stream position `p` is the low 8 bits of a splitmix64 hash of (seed, p). `seed`
  identifies the connection. The values are 8-bit, so byte values recur, but the
  per-position pattern does not: systematic corruption -- a wrong run, a misrouted
  chunk, a byte from another connection -- is caught near-certainly, while a lone
  single-byte reorder or duplicate aliases ~1/256. It is generated per position (no
  template to bulk-copy), the price of a stream unique per connection; the per-run
  byte volume is bounded by the orchestrator so generating it is not the bottleneck.
  """
  fun byte(seed: U64, p: USize): U8 =>
    var z: U64 = seed + (p.u64() * 0x9E3779B97F4A7C15)
    z = (z xor (z >> 30)) * 0xBF58476D1CE4E5B9
    z = (z xor (z >> 27)) * 0x94D049BB133111EB
    (z xor (z >> 31)).u8()

  fun make(seed: U64, start: USize, len: USize): Array[U8] iso^ =>
    recover
      let a = Array[U8](len)
      var i: USize = 0
      while i < len do
        a.push(byte(seed, start + i))
        i = i + 1
      end
      a
    end

  fun make_chunks(seed: U64, start: USize, total: USize, nchunks: USize)
    : Array[ByteSeq] val
  =>
    """
    The same stream as `make`, split across `nchunks` buffers for a vectored
    `send` -- contiguous over `start .. start + total`, so the echo verifies
    identically regardless of write shape.
    """
    // COUPLING: this allocates `nchunks` buffer objects per call regardless of
    // payload size (the extras are zero-length when nchunks > total). The
    // orchestrator's memory budget models peak memory as
    // OBJ_BYTES * concurrency * messages * writev_chunks off exactly this count
    // (est_peak_bytes in orchestrate_tcp.py) -- change how many objects this
    // creates and the budget can let an out-of-memory draw through.
    recover val
      let out = Array[ByteSeq]
      // Clamp to `total` so a small-payload draw (payload < nchunks) doesn't create
      // zero-length buffers -- lori's _enqueue drops empties, so they'd be pure
      // allocation churn. Coverage-neutral: the multi-batch path needs payload >=
      // chunks, where this leaves nchunks untouched.
      let n = if nchunks == 0 then 1 else nchunks.min(total.max(1)) end
      var done: USize = 0
      var c: USize = 0
      while c < n do
        let this_len = if c == (n - 1) then total - done else total / n end
        out.push(recover val
          let b = Array[U8](this_len)
          var i: USize = 0
          while i < this_len do
            b.push(byte(seed, start + done + i))
            i = i + 1
          end
          b
        end)
        done = done + this_len
        c = c + 1
      end
      out
    end

primitive _KeystreamSelfCheck
  """
  Guards the oracle's core before the run. The client both generates its payload
  and verifies the echo with `_Keystream.byte`, so a degenerate keystream (constant
  output, or one that ignores the seed) would make every connection verify against
  matching-but-wrong data -- the swarm would pass while catching nothing. A sanity
  guard, not a proof: it checks a representative seed pair for the two properties the
  oracle relies on, and aborts loudly if either fails.
  """
  fun apply() =>
    // Distinct connection seeds must produce distinct streams, or a byte from
    // another connection wouldn't fail the check. Seeds 0 and 1 are the first two
    // connection ids.
    var seeds_differ = false
    var p: USize = 0
    while p < 256 do
      if _Keystream.byte(0, p) != _Keystream.byte(1, p) then
        seeds_differ = true
        break
      end
      p = p + 1
    end
    // A single seed must vary across positions, or corruption within a connection
    // wouldn't fail the check.
    var seed_varies = false
    let first = _Keystream.byte(0, 0)
    var q: USize = 1
    while q < 256 do
      if _Keystream.byte(0, q) != first then
        seed_varies = true
        break
      end
      q = q + 1
    end
    if not (seeds_differ and seed_varies) then
      // Mirror the file's other abort paths: a FAIL marker on stdout for the log,
      // plus a diagnostic on stderr, then a non-zero exit.
      @printf("FAIL: keystream self-check\n".cstring())
      @fprintf(@pony_os_stderr(),
        "FATAL: _Keystream self-check failed -- the echo oracle is degenerate\n"
          .cstring())
      @exit(1)
    end

actor Spawner
  """
  Drives the run. Once the listener is up it keeps `concurrency` connections in
  flight at a time, refilling as each finishes, until `connections` have been
  spawned. It tallies every connection's terminal state (verified, mismatched,
  short, connect-failed), emits a heartbeat carrying the completed count on a
  fixed wall-clock timer (the orchestrator's watchdog reads that count and fails
  the run only if it stops advancing), and prints the pass/fail report when the
  last connection is accounted for.
  """
  let _config: _Config
  let _connect_auth: TCPConnectAuth
  var _port: String = ""
  var _listener: (SwarmListener | None) = None
  var _started: Bool = false
  var _spawned: USize = 0
  var _inflight: USize = 0
  var _completed: USize = 0
  var _failed: USize = 0
  var _verified: USize = 0
  var _mismatched: USize = 0
  var _finished: Bool = false
  // Started in listener_ready, disposed at finish. See heartbeat_tick.
  let _timers: Timers = Timers

  new create(config: _Config, connect_auth: TCPConnectAuth) =>
    _config = config
    _connect_auth = connect_auth

  be listener_ready(listener: SwarmListener, port: String) =>
    _listener = listener
    _port = port
    if not _started then
      _started = true
      // Heartbeat on a wall-clock timer, not per-completion: the orchestrator's
      // watchdog decides "hang" from whether `done` advances between heartbeats,
      // so liveness must be signalled on a fixed cadence a slow run can always
      // meet, independent of how fast connections complete. The interval must
      // stay well under the orchestrator's --no-progress-seconds window.
      let interval: U64 = 5_000_000_000  // 5s
      _timers(Timer(_HeartbeatTimer(this), interval, interval))
      _refill()
    end

  be connection_done(verified: Bool, mismatch: Bool) =>
    _inflight = _inflight - 1
    _completed = _completed + 1
    if verified then _verified = _verified + 1 end
    if mismatch then _mismatched = _mismatched + 1 end
    _refill()

  be connection_failed() =>
    _inflight = _inflight - 1
    _failed = _failed + 1
    _refill()

  be heartbeat_tick() =>
    // Fired by _HeartbeatTimer on a fixed wall-clock cadence. Prints the current
    // completed count so the orchestrator can see progress advancing; a run that
    // has stopped completing connections stops advancing `done` (the line keeps
    // coming), which is how the watchdog tells a slow run from a hang.
    if not _finished then _emit_heartbeat() end

  fun _emit_heartbeat() =>
    let done = _completed + _failed
    // Flushed: a block-buffered line would not reach the watchdog until the buffer
    // fills, which would defeat the no-progress detection.
    @printf("HEARTBEAT done=%zu of %zu\n".cstring(), done, _config.connections)
    @fflush(@pony_os_stdout())

  fun ref _refill() =>
    while (_inflight < _config.concurrency) and (_spawned < _config.connections)
    do
      SwarmClient(this, _config, _spawned, _connect_auth, _port)
      _spawned = _spawned + 1
      _inflight = _inflight + 1
    end
    _try_finish()

  fun ref _try_finish() =>
    if (not _finished)
      and (_spawned >= _config.connections)
      and (_inflight == 0)
    then
      _finished = true
      // A final heartbeat with the true completed count before the timer stops:
      // the last wave completes after the previous tick, so this records the full
      // total and resets the watchdog's clock at finish (the shutdown that follows
      // gets a fresh no-progress window).
      _emit_heartbeat()
      // Stop the heartbeat timer so the runtime can reach quiescence: a live
      // repeating timer is a noisy ASIO event that would keep the program from
      // exiting after the last connection is done.
      _timers.dispose()
      _report()
      match _listener
      | let l: SwarmListener => l.dispose()
      end
      _listener = None
    end

  fun _report() =>
    // %zu (size_t) is the portable format for USize -- %lu is 32-bit on Windows.
    // COUPLING: RESULT is printed before any FAIL line. The orchestrator's
    // parse_result reads the tally off RESULT with a \b-anchored `failed=`; the
    // FAIL line below repeats `connect_failed=`, so a FAIL emitted first would be
    // misread. (orchestrate_tcp.py: parse_result)
    @printf(("RESULT connections=%zu spawned=%zu completed=%zu failed=%zu "
      + "verified=%zu mismatched=%zu\n").cstring(),
      _config.connections, _spawned, _completed, _failed, _verified,
      _mismatched)
    // This is a stress test, not fault injection: every connection must connect,
    // exchange, and verify its echo. Anything less is a failure -- a connect that
    // failed (a bug, or a mis-set-up harness exhausting ports), a short echo (a
    // connection that closed with fewer bytes than it sent), or a byte mismatch.
    // All of them leave verified < connections.
    if _verified == _config.connections then
      @printf("PASS\n".cstring())
    else
      let truncated = (_completed - _verified) - _mismatched
      @printf(("FAIL: %zu of %zu connections did not verify "
        + "(connect_failed=%zu truncated=%zu mismatched=%zu)\n").cstring(),
        _config.connections - _verified, _config.connections,
        _failed, truncated, _mismatched)
      @exit(1)
    end

class _HeartbeatTimer is TimerNotify
  """
  Fires the Spawner's wall-clock heartbeat. Repeats on a fixed interval until the
  Spawner disposes the timer when the run finishes.
  """
  let _spawner: Spawner

  new iso create(spawner: Spawner) =>
    _spawner = spawner

  fun ref apply(timer: Timer, count: U64): Bool =>
    _spawner.heartbeat_tick()
    true

actor SwarmListener is TCPListenerActor
  """
  The listen side. Hands each accepted connection an `EchoServer`, and once the
  listener has a bound port tells the `Spawner` to start dialing.
  """
  let _spawner: Spawner
  let _config: _Config
  let _listen_auth: TCPListenAuth
  var _tcp_listener: TCPListener = TCPListener.none()

  new create(spawner: Spawner, config: _Config, listen_auth: TCPListenAuth) =>
    _spawner = spawner
    _config = config
    _listen_auth = listen_auth
    // limit = None: unbounded accepts. Concurrency is enforced client-side by the
    // Spawner (it keeps `concurrency` connections in flight), matching the source
    // engine's unlimited listener.
    _tcp_listener = TCPListener(listen_auth, config.host, config.port, this
      where limit = None)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): EchoServer =>
    EchoServer(TCPServerAuth(_listen_auth), fd, _config)

  fun ref _on_listening() =>
    // port().string() already returns a sendable `String iso^`; no `recover`
    // (which couldn't touch the `_tcp_listener` field anyway).
    let port = _tcp_listener.local_address().port().string()
    _spawner.listener_ready(this, consume port)

  fun ref _on_listen_failure() =>
    @printf("FAIL: listener could not start\n".cstring())
    @exit(1)

actor EchoServer is (TCPConnectionActor & ServerLifecycleEventReceiver)
  """
  The server half of a connection: echoes every byte it receives straight back,
  unmodified. The client's keystream oracle checks what comes back, so the server
  stays deliberately dumb -- any corruption it introduced would be
  indistinguishable from a real stack bug.

  Because lori's `send()` does not queue on backpressure, the server handles it:
  when it cannot echo a chunk it stashes that one chunk and `mute()`s (which stops
  further reads, so at most one chunk is ever held), then sends the stash and
  `unmute()`s from `_on_unthrottled`.
  """
  let _config: _Config
  var _tcp_connection: TCPConnection = TCPConnection.none()
  var _pending: (Array[U8] iso | None) = None
  var _since_yield: USize = 0

  new create(auth: TCPServerAuth, fd: U32, config: _Config) =>
    _config = config
    _tcp_connection = TCPConnection.server(auth, fd, this, this,
      config.read_buffer())
    _set_framing()

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _set_framing() =>
    if _config.expect_frame > 0 then
      // Unreachable branches: expect_frame is clamped to read_buffer_size (the
      // buffer minimum) and is >= 1 when set, so buffer_until always succeeds.
      match MakeBufferSize(_config.expect_frame)
      | let b: BufferSize =>
        match _tcp_connection.buffer_until(b)
        | BufferUntilSet => None
        | BufferSizeAboveMinimum => _Unreachable()
        end
      else
        _Unreachable()
      end
    end

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    let n = data.size()

    // Echo. Check is_writeable() BEFORE send(): send(consume data) consumes the
    // buffer even on a SendError, so a "try then stash" would drop it.
    if _tcp_connection.is_writeable() then
      _tcp_connection.send(consume data)
    else
      _pending = consume data
      _tcp_connection.mute()
      // Muted -- reads have stopped, so skip the yield bookkeeping below.
      return KeepReading
    end

    _since_yield = _since_yield + n
    if _since_yield >= _config.yield_after_reading then
      _since_yield = 0
      return YieldReading
    end

    KeepReading

  fun ref _on_unthrottled() =>
    // Backpressure cleared. If we stashed a chunk, echo it (we are writeable now)
    // and resume reading.
    match _pending = None
    | let d: Array[U8] iso =>
      _tcp_connection.send(consume d)
      _tcp_connection.unmute()
    | None =>
      None
    end

actor SwarmClient is (TCPConnectionActor & ClientLifecycleEventReceiver)
  """
  The client half of a connection. On connect it pumps its whole keystream --
  `messages` payloads of `payload_size` bytes, via `write` or `writev` -- handing
  the connection one message at a time while it is writeable and resuming from
  `_on_unthrottled` after backpressure. It verifies the echo byte for byte against
  the same keystream as it comes back. When it has read back everything it will
  send it closes (gracefully, or muted for a hard close) and reports to the
  `Spawner` whether the echo verified.
  """
  let _spawner: Spawner
  let _config: _Config
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _seed: U64
  // The total bytes this connection will send (and must read back). Fixed intent,
  // independent of send progress -- the verify closes on reaching it.
  let _target_total: USize
  var _sent_total: USize = 0
  var _messages_sent: USize = 0
  var _recv_count: USize = 0
  var _since_yield: USize = 0
  var _mismatch: Bool = false
  var _reported: Bool = false
  var _closing: Bool = false

  new create(spawner: Spawner, config: _Config, id: USize,
    connect_auth: TCPConnectAuth, port: String)
  =>
    _spawner = spawner
    _config = config
    // The connection id keys its own byte stream; distinct ids give distinct,
    // unrelated streams (splitmix diffuses adjacent seeds), so a byte from another
    // connection fails this connection's check.
    _seed = id.u64()
    _target_total = config.payload_size * config.messages
    _tcp_connection = TCPConnection.client(connect_auth, config.host, port, "",
      this, this, config.read_buffer())
    _set_framing()

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _set_framing() =>
    if _config.expect_frame > 0 then
      // Unreachable branches: see EchoServer._set_framing.
      match MakeBufferSize(_config.expect_frame)
      | let b: BufferSize =>
        match _tcp_connection.buffer_until(b)
        | BufferUntilSet => None
        | BufferSizeAboveMinimum => _Unreachable()
        end
      else
        _Unreachable()
      end
    end

  fun ref _on_connected() =>
    if _target_total == 0 then
      _close()
    else
      _pump()
    end

  fun ref _pump() =>
    // Hand the connection one message at a time while it is writeable. On a
    // plaintext connection, is_writeable() true means send() accepts the buffer
    // and returns a SendToken, so the return is safe to discard. A message that
    // hits backpressure mid-flush is still accepted -- lori queues the
    // remainder -- and the NEXT is_writeable() check then fails, so we resume
    // from _on_unthrottled.
    if _closing then
      return
    end
    while (_messages_sent < _config.messages)
      and _tcp_connection.is_writeable()
    do
      if _config.use_writev then
        _tcp_connection.send(_Keystream.make_chunks(_seed, _sent_total,
          _config.payload_size, _config.writev_chunks))
      else
        _tcp_connection.send(_Keystream.make(_seed, _sent_total,
          _config.payload_size))
      end
      _sent_total = _sent_total + _config.payload_size
      _messages_sent = _messages_sent + 1
    end

  fun ref _on_unthrottled() =>
    _pump()

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    let n = data.size()
    try
      var i: USize = 0
      while i < n do
        let pos = _recv_count + i
        // A byte past the total we asked to have echoed back is over-delivery -- a
        // teardown/re-delivery bug, a class this harness exists to catch. Keep
        // verifying after _close() (lori's graceful _Closing still reads) so such a
        // byte is flagged, not silently dropped.
        if pos >= _target_total then
          _mismatch = true
        elseif data(i)? != _Keystream.byte(_seed, pos) then
          _mismatch = true
        end
        i = i + 1
      end
    else
      // Unreachable: i < n == data.size() bounds every access.
      _Unreachable()
    end
    _recv_count = _recv_count + n

    if not _closing then
      if _recv_count >= _target_total then
        _close()
      else
        _since_yield = _since_yield + n
        if _since_yield >= _config.yield_after_reading then
          _since_yield = 0
          return YieldReading
        end
      end
    end

    KeepReading

  fun ref _on_connection_failure(reason: ConnectionFailureReason) =>
    if not _reported then
      _reported = true
      _spawner.connection_failed()
    end

  fun ref _on_closed() =>
    if not _reported then
      _reported = true
      let verified = (not _mismatch) and (_recv_count >= _target_total)
      _spawner.connection_done(verified, _mismatch)
    end

  fun ref _close() =>
    _closing = true
    if _config.close_hard then
      _tcp_connection.mute()
    end
    _tcp_connection.close()

actor Main
  """
  Parses the flags into a `_Config`, stands up the echo listener, and starts the
  run. All the work happens in the `Spawner` and the per-connection actors.
  """
  new create(env: Env) =>
    // Guard the echo oracle before doing anything: a degenerate keystream would let
    // the whole swarm pass while catching nothing.
    _KeystreamSelfCheck()
    let config = _Config(_Flags(env.args))
    let spawner = Spawner(config, TCPConnectAuth(env.root))
    SwarmListener(spawner, config, TCPListenAuth(env.root))

primitive _Unreachable
  """
  For a branch the compiler forces us to write but that we know is dead: if it is
  ever reached, crash with the source location rather than silently continuing on
  corrupt state.
  """
  fun apply(loc: SourceLoc = __loc) =>
    @fprintf(@pony_os_stderr(),
      ("Reached unreachable code at %s:%s\n" +
       "Please open an issue at https://github.com/ponylang/lori/issues\n")
       .cstring(),
      loc.file().cstring(), loc.line().string().cstring())
    @exit(1)
