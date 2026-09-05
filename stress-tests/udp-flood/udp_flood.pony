"""
UDP flood stress engine for lori.

A count-driven UDP workload for stressing lori's UDP stack. A fixed number of
clients send stamped datagrams to a server through a single echo socket; the
server echoes each datagram back to its sender, and the client verifies the
echo byte-for-byte against a per-client keystream.

Unlike the TCP swarm, there is no connection lifecycle to stress: UDP sockets
bind, send, receive, and close. The point is to exercise the readiness event
delivery path under sustained datagram volume, verifying that the ASIO backend
(ProcessSocketNotifications on Windows, epoll on Linux, kqueue on macOS)
correctly delivers persistent edge-triggered notifications for UDP sockets
across many read-loop re-entries.

Each swarm dimension exercises a distinct code path in `udp_socket.pony`:

* `--datagrams` / `--payload-size` -- volume and per-datagram size.
* `--batch-size` -- how many datagrams a client sends before waiting for echoes.
  With batch 1 the client waits for each echo before sending the next (one
  event delivery per round-trip). Larger batches burst datagrams and exercise
  the read loop's datagram-count and byte budgets.
* `--clients` -- concurrent client sockets sending to the same server.
* `--read-buffer-size` -- the per-socket read buffer, which sets the byte
  budget in `_pending_reads`.
* `--max-datagrams-per-turn` -- the per-turn datagram ceiling in
  `_pending_reads`. Small values exercise the `_read_again` yield path.

Oracles:

* Echo integrity -- each client sends a per-client pseudo-random byte stream
  (byte at position p is the low 8 bits of a splitmix64 hash of (client-id,
  p)), and verifies every echoed byte against it. Position-based: the Nth echo
  must match the Nth datagram sent (UDP preserves order on loopback).
* Conservation -- every client must send and verify all its datagrams.
* Crash / assert -- debug build, asserts on.

On success (every client verified) the engine prints its RESULT line and PASS,
then returns. Anything short of full verification prints FAIL and exits
non-zero.
"""
use "../../lori"
use "cli"
use "constrained_types"
use "time"

use @printf[I32](fmt: Pointer[U8] tag, ...)
use @fprintf[I32](stream: Pointer[U8] tag, fmt: Pointer[U8] tag, ...)
use @fflush[I32](stream: Pointer[U8] tag)
use @pony_os_stdout[Pointer[U8]]()
use @pony_os_stderr[Pointer[U8]]()
use @exit[None](status: I32)

primitive _Flag
  """
  The command-line flag names, in one place. `_FloodSpec` (which declares them)
  and `_MakeConfig` (which reads them) both name flags through here, so a
  mistyped name is a compile error rather than a silently ignored option or a
  value that reads back as zero.
  """
  fun host(): String => "host"
  fun port(): String => "port"
  fun datagrams(): String => "datagrams"
  fun payload_size(): String => "payload-size"
  fun batch_size(): String => "batch-size"
  fun clients(): String => "clients"
  fun read_buffer_size(): String => "read-buffer-size"
  fun max_datagrams_per_turn(): String => "max-datagrams-per-turn"

primitive _FloodSpec
  """
  The command-line schema: every workload flag, its type, and its default.
  `Main` parses `env.args` against this, so a malformed or misspelled flag is
  a reported error rather than a silent default. The `cli` parser checks types
  and flag names; `_MakeConfig` checks value domains.
  """
  fun apply(): CommandSpec ? =>
    CommandSpec.leaf(
      "udp-flood",
      "UDP flood stress engine for lori.",
      [ OptionSpec.string(
          _Flag.host(),
          "server bind host"
          where default' = "localhost")
        OptionSpec.string(
          _Flag.port(),
          "server bind port (0 = ephemeral)"
          where default' = "0")
        OptionSpec.u64(
          _Flag.datagrams(),
          "datagrams each client sends"
          where default' = 1000)
        OptionSpec.u64(
          _Flag.payload_size(),
          "bytes per datagram"
          where default' = 64)
        OptionSpec.u64(
          _Flag.batch_size(),
          "datagrams per send burst"
          where default' = 10)
        OptionSpec.u64(
          _Flag.clients(),
          "concurrent client sockets"
          where default' = 4)
        OptionSpec.u64(
          _Flag.read_buffer_size(),
          "per-socket read buffer size"
          where default' = 16384)
        OptionSpec.u64(
          _Flag.max_datagrams_per_turn(),
          "datagram ceiling per read turn"
          where default' = 256)
      ])? .> add_help(where descr' = "print usage and exit")?

class val _Config
  """
  The validated workload configuration. Built only by `_MakeConfig`, from a
  parsed command line whose every value it has already checked -- so the rest
  of the engine can trust these fields without re-checking.
  """
  let host: String
  let port: String
  let datagrams: USize
  let payload_size: USize
  let batch_size: USize
  let clients: USize
  let read_buffer_size: USize
  let max_datagrams_per_turn: USize

  new val _create(
    host': String,
    port': String,
    datagrams': USize,
    payload_size': USize,
    batch_size': USize,
    clients': USize,
    read_buffer_size': USize,
    max_datagrams_per_turn': USize)
  =>
    host = host'
    port = port'
    datagrams = datagrams'
    payload_size = payload_size'
    batch_size = batch_size'
    clients = clients'
    read_buffer_size = read_buffer_size'
    max_datagrams_per_turn = max_datagrams_per_turn'

  fun read_buffer(): ReadBufferSize =>
    match MakeReadBufferSize(read_buffer_size)
    | let r: ReadBufferSize => r
    else
      _Unreachable()
      DefaultReadBufferSize()
    end

primitive _MakeConfig
  """
  Reads and validates the workload flags off a parsed `Command`, returning a
  `_Config` when every value is in range, or a `ValidationFailure` naming the
  first bad one. Validation lives here, at the construction boundary, because
  `Main` still holds the `Env` to report the failure -- a `_Config` cannot.
  """
  fun apply(cmd: Command box): (_Config | ValidationFailure) =>
    let datagrams = cmd.option(_Flag.datagrams()).u64().usize()
    if datagrams < 1 then
      return recover val
        ValidationFailure("--datagrams must be at least 1")
      end
    end
    let payload_size = cmd.option(_Flag.payload_size()).u64().usize()
    if payload_size < 1 then
      return recover val
        ValidationFailure("--payload-size must be at least 1")
      end
    end
    let batch_size = cmd.option(_Flag.batch_size()).u64().usize()
    if batch_size < 1 then
      return recover val
        ValidationFailure("--batch-size must be at least 1")
      end
    end
    let clients = cmd.option(_Flag.clients()).u64().usize()
    if clients < 1 then
      return recover val
        ValidationFailure("--clients must be at least 1")
      end
    end
    let read_buffer_size = cmd.option(_Flag.read_buffer_size()).u64().usize()
    if read_buffer_size < 1 then
      return recover val
        ValidationFailure("--read-buffer-size must be at least 1")
      end
    end
    try
      payload_size.mul_partial(datagrams)?
    else
      return recover val
        ValidationFailure("--payload-size * --datagrams overflows USize")
      end
    end
    if payload_size > read_buffer_size then
      return recover val
        ValidationFailure(
          "--payload-size (" + payload_size.string() +
            ") must not exceed --read-buffer-size (" +
            read_buffer_size.string() + ")")
      end
    end
    let max_datagrams_per_turn =
      cmd.option(_Flag.max_datagrams_per_turn()).u64().usize()
    if max_datagrams_per_turn < 1 then
      return recover val
        ValidationFailure("--max-datagrams-per-turn must be at least 1")
      end
    end

    _Config._create(
      cmd.option(_Flag.host()).string(),
      cmd.option(_Flag.port()).string(),
      datagrams,
      payload_size,
      batch_size,
      clients,
      read_buffer_size,
      max_datagrams_per_turn)

primitive _Keystream
  """
  The echo oracle checks a per-client pseudo-random byte stream: the byte at
  stream position `p` is the low 8 bits of a splitmix64 hash of (seed, p).
  `seed` identifies the client. The values are 8-bit, so byte values recur,
  but the per-position pattern does not: systematic corruption -- a wrong
  datagram, a byte from another client -- is caught near-certainly, while a
  lone single-byte error aliases ~1/256. It is generated per position (no
  template to bulk-copy), the price of a stream unique per client; the
  per-run byte volume is bounded by the orchestrator so generating it is not
  the bottleneck.
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

primitive _KeystreamSelfCheck
  """
  Guards the oracle's core before the run. The client both generates its
  payload and verifies the echo with `_Keystream.byte`, so a degenerate
  keystream (constant output, or one that ignores the seed) would make every
  client verify against matching-but-wrong data -- the flood would pass while
  catching nothing. A sanity guard, not a proof: it checks a representative
  seed pair for the two properties the oracle relies on, and aborts loudly if
  either fails.
  """
  fun apply() =>
    var seeds_differ = false
    var p: USize = 0
    while p < 256 do
      if _Keystream.byte(0, p) != _Keystream.byte(1, p) then
        seeds_differ = true
        break
      end
      p = p + 1
    end
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
      @printf("FAIL: keystream self-check\n".cstring())
      @fprintf(
        @pony_os_stderr(),
        "FATAL: _Keystream self-check failed -- the echo oracle is degenerate\n"
          .cstring())
      @exit(1)
    end

actor Spawner
  """
  Coordinates server and client lifecycle. Spawns clients once the server
  is bound, collects completion tallies, and prints the RESULT/PASS/FAIL line.
  """
  let _config: _Config
  let _udp_auth: UDPAuth
  var _server: (FloodServer | None) = None
  var _started: Bool = false
  var _spawned: USize = 0
  var _completed: USize = 0
  var _verified: USize = 0
  var _mismatched: USize = 0
  var _bind_failed: USize = 0
  var _finished: Bool = false
  let _timers: Timers = Timers

  new create(config: _Config, udp_auth: UDPAuth) =>
    _config = config
    _udp_auth = udp_auth

  be server_ready(server: FloodServer, addr: NetAddress val) =>
    _server = server
    if not _started then
      _started = true
      let interval: U64 = 5_000_000_000
      _timers(Timer(_HeartbeatTimer(this), interval, interval))
      var i: USize = 0
      while i < _config.clients do
        FloodClient(this, _config, i, _udp_auth, addr)
        _spawned = _spawned + 1
        i = i + 1
      end
    end

  be server_bind_failed() =>
    @printf("FAIL: server could not bind\n".cstring())
    @exit(1)

  be client_done(verified: Bool, mismatch: Bool) =>
    """
    Record one client's completion and check whether all clients are done.
    """
    _completed = _completed + 1
    if verified then _verified = _verified + 1 end
    if mismatch then _mismatched = _mismatched + 1 end
    _try_finish()

  be client_bind_failed() =>
    _bind_failed = _bind_failed + 1
    _completed = _completed + 1
    _try_finish()

  be heartbeat_tick() =>
    if not _finished then _emit_heartbeat() end

  fun _emit_heartbeat() =>
    @printf(
      "HEARTBEAT done=%zu of %zu\n".cstring(),
      _completed,
      _config.clients)
    @fflush(@pony_os_stdout())

  fun ref _try_finish() =>
    if (not _finished) and (_completed >= _config.clients) then
      _finished = true
      _emit_heartbeat()
      _timers.dispose()
      _report()
      match _server
      | let s: FloodServer => s.dispose()
      end
      _server = None
    end

  fun _report() =>
    @printf(
      ("RESULT clients=%zu completed=%zu verified=%zu " +
        "mismatched=%zu bind_failed=%zu\n").cstring(),
      _config.clients,
      _completed,
      _verified,
      _mismatched,
      _bind_failed)
    if _verified == _config.clients then
      @printf("PASS\n".cstring())
    else
      @printf(
        "FAIL: %zu of %zu clients did not verify\n".cstring(),
        _config.clients - _verified,
        _config.clients)
      @exit(1)
    end

class _HeartbeatTimer is TimerNotify
  """
  Fires the Spawner's wall-clock heartbeat. Repeats on a fixed interval until
  the Spawner disposes the timer when the run finishes.
  """
  let _spawner: Spawner

  new iso create(spawner: Spawner) =>
    _spawner = spawner

  fun ref apply(timer: Timer, count: U64): Bool =>
    _spawner.heartbeat_tick()
    true

actor FloodServer is (UDPSocketActor & UDPLifecycleEventReceiver)
  """
  Echo server. Echoes each received datagram back to its sender. When
  `send_to` returns `SendToWouldBlock`, the datagram is stashed and a
  deferred `_drain_stash` behavior retries it.
  """
  let _spawner: Spawner
  let _config: _Config
  var _udp: UDPSocket = UDPSocket.none()
  embed _stash: Array[(Array[U8] val, NetAddress val)]
    = Array[(Array[U8] val, NetAddress val)]
  var _drain_scheduled: Bool = false

  new create(spawner: Spawner, config: _Config, udp_auth: UDPAuth) =>
    _spawner = spawner
    _config = config
    _udp =
      UDPSocket(
        udp_auth, config.host, config.port, this, this, config.read_buffer()
        where max_datagrams_per_turn = config.max_datagrams_per_turn)

  fun ref _socket(): UDPSocket => _udp

  fun ref _on_bound() =>
    _udp.set_so_rcvbuf(4194304)
    _udp.set_so_sndbuf(4194304)
    let addr = _udp.local_address()
    _spawner.server_ready(this, addr)

  fun ref _on_bind_failure() =>
    _spawner.server_bind_failed()

  fun ref _on_received(data: Array[U8] iso, from: NetAddress val)
    : ReadAction
  =>
    let d: Array[U8] val = consume data
    if _stash.size() > 0 then
      _stash.push((d, from))
      _schedule_drain()
    else
      match \exhaustive\ _udp.send_to(d, from)
      | SendToOk => None
      | SendToWouldBlock =>
        _stash.push((d, from))
        _schedule_drain()
      | SendToError => None
      | SendToNotOpen => None
      end
    end
    KeepReading

  fun ref _schedule_drain() =>
    if not _drain_scheduled then
      _drain_scheduled = true
      _drain_stash()
    end

  be _drain_stash() =>
    _drain_scheduled = false
    while _stash.size() > 0 do
      try
        (let d, let f) = _stash(0)?
        match \exhaustive\ _udp.send_to(d, f)
        | SendToOk =>
          try _stash.shift()? else _Unreachable() end
        | SendToWouldBlock =>
          _schedule_drain()
          return
        | SendToError =>
          try _stash.shift()? else _Unreachable() end
        | SendToNotOpen =>
          try _stash.shift()? else _Unreachable() end
        end
      else
        _Unreachable()
      end
    end

  fun ref _on_closed() =>
    None

actor FloodClient is (UDPSocketActor & UDPLifecycleEventReceiver)
  """
  Sends datagrams in batches to the server and verifies echoed data against
  a per-client keystream. Reports verified/mismatch status to the `Spawner`
  when all datagrams have been echoed or when the socket closes.
  """
  let _spawner: Spawner
  let _config: _Config
  var _udp: UDPSocket = UDPSocket.none()
  let _seed: U64
  let _server_addr: NetAddress val
  var _send_cursor: USize = 0
  var _batch_sent: USize = 0
  var _recv_cursor: USize = 0
  var _mismatch: Bool = false
  var _reported: Bool = false

  new create(
    spawner: Spawner,
    config: _Config,
    id: USize,
    udp_auth: UDPAuth,
    server_addr: NetAddress val)
  =>
    _spawner = spawner
    _config = config
    _seed = id.u64()
    _server_addr = server_addr
    _udp =
      UDPSocket(
        udp_auth, config.host, "0", this, this, config.read_buffer()
        where max_datagrams_per_turn = config.max_datagrams_per_turn)

  fun ref _socket(): UDPSocket => _udp

  fun ref _on_bound() =>
    _udp.set_so_rcvbuf(1048576)
    _udp.set_so_sndbuf(1048576)
    _pump()

  fun ref _on_bind_failure() =>
    if not _reported then
      _reported = true
      _spawner.client_bind_failed()
    end

  fun ref _pump() =>
    while (_batch_sent < _config.batch_size) and
      (_send_cursor < _config.datagrams)
    do
      let start = _send_cursor * _config.payload_size
      let payload = _Keystream.make(_seed, start, _config.payload_size)
      match \exhaustive\ _udp.send_to(consume payload, _server_addr)
      | SendToOk =>
        _send_cursor = _send_cursor + 1
        _batch_sent = _batch_sent + 1
      | SendToWouldBlock =>
        _retry_send()
        return
      | SendToError =>
        @fprintf(
          @pony_os_stderr(),
          "client %zu: send_to returned SendToError\n".cstring(),
          _seed)
        _close_and_report()
        return
      | SendToNotOpen =>
        _close_and_report()
        return
      end
    end

  be _retry_send() =>
    if not _reported then
      _pump()
    end

  fun ref _on_received(data: Array[U8] iso, from: NetAddress val)
    : ReadAction
  =>
    let n = data.size()
    try
      var i: USize = 0
      let start = _recv_cursor * _config.payload_size
      while i < n do
        if data(i)? != _Keystream.byte(_seed, start + i) then
          _mismatch = true
        end
        i = i + 1
      end
    else
      _Unreachable()
    end
    _recv_cursor = _recv_cursor + 1

    if _recv_cursor >= _send_cursor then
      if _send_cursor >= _config.datagrams then
        _close_and_report()
      else
        _batch_sent = 0
        _pump()
      end
    end

    KeepReading

  fun ref _on_closed() =>
    if not _reported then
      _reported = true
      let verified = (not _mismatch) and (_recv_cursor >= _config.datagrams)
      _spawner.client_done(verified, _mismatch)
    end

  fun ref _close_and_report() =>
    _udp.close()

actor Main
  """
  Parses and validates the flags into a `_Config`, stands up the echo server,
  and starts the run. A malformed, misspelled, or out-of-range flag is reported
  here and exits non-zero, rather than running the wrong workload silently. All
  the work happens in the `Spawner` and the per-client actors.
  """
  new create(env: Env) =>
    _KeystreamSelfCheck()

    let spec =
      try
        _FloodSpec()?
      else
        _Unreachable()
        return
      end

    let cmd =
      match \exhaustive\ CommandParser(spec).parse(env.args)
      | let c: Command => c
      | let ch: CommandHelp =>
        ch.print_help(env.out)
        return
      | let se: SyntaxError =>
        env.err.print(se.string())
        env.exitcode(1)
        return
      end

    let config =
      match \exhaustive\ _MakeConfig(cmd)
      | let c: _Config => c
      | let vf: ValidationFailure =>
        for e in vf.errors().values() do
          env.err.print(e)
        end
        env.exitcode(1)
        return
      end

    let udp_auth = UDPAuth(env.root)
    let spawner = Spawner(config, udp_auth)
    FloodServer(spawner, config, udp_auth)

primitive _Unreachable
  """
  For a branch the compiler forces us to write but that we know is dead: if it
  is ever reached, crash with the source location rather than silently
  continuing on corrupt state.
  """
  fun apply(loc: SourceLoc = __loc) =>
    @fprintf(
      @pony_os_stderr(),
      ("Reached unreachable code at %s:%s\n" +
        "Please open an issue at https://github.com/ponylang/lori/issues\n")
        .cstring(),
      loc.file().cstring(),
      loc.line().string().cstring())
    @exit(1)
