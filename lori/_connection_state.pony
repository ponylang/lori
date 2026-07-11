use "ssl/net"

trait _ConnectionState
  """
  One state in the connection lifecycle. `TCPConnection._state` holds the
  current one, and lifecycle-gated operations dispatch through it: each state
  answers what happens in it, and delegates the actual work to `TCPConnection`.
  """
  fun ref own_event(conn: TCPConnection ref, flags: U32)
    """Handle an ASIO event for this connection's own socket event."""
  fun ref foreign_event(conn: TCPConnection ref, event: AsioEventID,
    flags: U32)
    """
    Handle an ASIO event that is not this connection's socket event (a Happy
    Eyeballs straggler).
    """
  fun ref send(conn: TCPConnection ref,
    data: (ByteSeq | ByteSeqIter)): (SendToken | SendError)
    """Send data, or return why it can't be sent in this state."""
  fun ref close(conn: TCPConnection ref)
    """Graceful close from this state."""
  fun ref hard_close(conn: TCPConnection ref, cause: _HardCloseCause)
    """
    Non-graceful close from this state, routing `cause` to a failure callback.
    """
  fun ref start_tls(conn: TCPConnection ref, ssl_ctx: SSLContext val,
    host: String): (None | StartTLSError)
    """Upgrade to TLS, or return why it can't happen in this state."""
  fun ref read_again(conn: TCPConnection ref)
    """Resume reading after a yield, if this state still reads."""
  fun ref ssl_handshake_complete(conn: TCPConnection ref,
    s: EitherLifecycleEventReceiver ref)
    """The SSL session reached `SSLReady`. Only the handshake states act."""
  fun keepalive(conn: TCPConnection box, secs: U32)
    """Set TCP keepalive, if the socket is open in this state."""
  fun getsockopt(conn: TCPConnection box, level: I32, option_name: I32,
    option_max_size: USize): (U32, Array[U8] iso^)
    """Raw `getsockopt`, or an error value if not open in this state."""
  fun getsockopt_u32(conn: TCPConnection box, level: I32,
    option_name: I32): (U32, U32)
    """`getsockopt` for a U32, or an error value if not open in this state."""
  fun setsockopt(conn: TCPConnection box, level: I32, option_name: I32,
    option: Array[U8]): U32
    """Raw `setsockopt`, or an error value if not open in this state."""
  fun setsockopt_u32(conn: TCPConnection box, level: I32, option_name: I32,
    option: U32): U32
    """`setsockopt` for a U32, or an error value if not open in this state."""
  fun ref idle_timeout(conn: TCPConnection ref,
    duration: (IdleTimeout | None))
    """Set or clear the idle timeout; states differ in whether they arm it."""
  fun ref set_timer(conn: TCPConnection ref,
    duration: TimerDuration): (TimerToken | SetTimerError)
    """Start a user timer, or return why it can't be started in this state."""
  fun is_open(): Bool
    """The connection is open for application I/O (`_Open`/`_TLSUpgrading`)."""
  fun is_closed(): Bool
    """The connection is closed or closing."""
  fun sends_allowed(): Bool
    """Sends are accepted in this state."""
  fun is_live(): Bool
    """
    Has a socket fd it can still do I/O on -- from the handshake through a
    graceful close still draining, but not before the fd exists or after a hard
    close tears it down. See the state table in AGENTS.md.
    """
  fun receive(event: AsioEventID, buffer: Pointer[U8] tag,
    size: USize): (SocketResult, USize)
    """Read from the socket. Only states that can receive perform it."""

class _ConnectionNone is _ConnectionState
  fun ref own_event(conn: TCPConnection ref, flags: U32) =>
    _Unreachable()

  fun ref foreign_event(conn: TCPConnection ref, event: AsioEventID,
    flags: U32)
  =>
    if not (AsioEvent.errored(flags) or AsioEvent.writeable(flags)
      or AsioEvent.readable(flags))
    then
      return
    end

    // The message flags and the event struct's disposable status can
    // disagree: a stale message may carry writeable/readable flags while
    // the event struct has already been marked disposable by a prior
    // unsubscribe. Check the struct before unsubscribing.
    if not PonyAsio.get_disposable(event) then
      PonyAsio.unsubscribe(event)
    end
    conn._close_event_fd(PonyAsio.event_fd(event))

  fun ref send(conn: TCPConnection ref,
    data: (ByteSeq | ByteSeqIter)): (SendToken | SendError)
  =>
    _Unreachable()
    SendErrorNotConnected

  fun ref close(conn: TCPConnection ref) =>
    _Unreachable()

  fun ref hard_close(conn: TCPConnection ref,
    cause: _HardCloseCause)
  =>
    // _finish_initialization is a self→self message queued during the
    // constructor. dispose() comes from an external actor. Different senders
    // have no ordering guarantee, so dispose() can arrive first — unlikely
    // but possible.
    None

  fun ref start_tls(conn: TCPConnection ref, ssl_ctx: SSLContext val,
    host: String): (None | StartTLSError)
  =>
    _Unreachable()
    StartTLSNotConnected

  fun ref read_again(conn: TCPConnection ref) =>
    _Unreachable()

  fun ref ssl_handshake_complete(conn: TCPConnection ref,
    s: EitherLifecycleEventReceiver ref)
  =>
    _Unreachable()

  fun keepalive(conn: TCPConnection box, secs: U32) => None

  fun getsockopt(conn: TCPConnection box, level: I32, option_name: I32,
    option_max_size: USize): (U32, Array[U8] iso^)
  =>
    (1, recover Array[U8] end)

  fun getsockopt_u32(conn: TCPConnection box, level: I32,
    option_name: I32): (U32, U32)
  =>
    (1, 0)

  fun setsockopt(conn: TCPConnection box, level: I32, option_name: I32,
    option: Array[U8]): U32
  =>
    1

  fun setsockopt_u32(conn: TCPConnection box, level: I32, option_name: I32,
    option: U32): U32
  =>
    1

  fun ref idle_timeout(conn: TCPConnection ref,
    duration: (IdleTimeout | None))
  =>
    conn._store_idle_timeout(duration)

  fun ref set_timer(conn: TCPConnection ref,
    duration: TimerDuration): (TimerToken | SetTimerError)
  =>
    SetTimerNotOpen

  fun is_open(): Bool => false
  fun is_closed(): Bool => false
  fun sends_allowed(): Bool => false
  fun is_live(): Bool => false

  fun receive(event: AsioEventID, buffer: Pointer[U8] tag,
    size: USize): (SocketResult, USize)
  =>
    _Unreachable()
    (SocketResultError, 0)

class _ClientConnecting is _ConnectionState
  fun ref own_event(conn: TCPConnection ref, flags: U32) =>
    _Unreachable()

  fun ref foreign_event(conn: TCPConnection ref, event: AsioEventID,
    flags: U32)
  =>
    // Check errored before the writeable/readable guard. An errored event
    // must NOT flow into _is_socket_connected — the FD might appear
    // "connected" via getsockopt(SO_ERROR) even though its ASIO subscription
    // is broken.
    if AsioEvent.errored(flags) then
      let fd = PonyAsio.event_fd(event)
      conn._decrement_inflight()
      conn._connecting_event_failed(event, fd)
      return
    end

    if not (AsioEvent.writeable(flags) or AsioEvent.readable(flags)) then
      return
    end

    let fd = PonyAsio.event_fd(event)
    conn._decrement_inflight()

    if conn._is_socket_connected(fd) then
      conn._establish_connection(event, fd)
    else
      conn._connecting_event_failed(event, fd)
    end

  fun ref send(conn: TCPConnection ref,
    data: (ByteSeq | ByteSeqIter)): (SendToken | SendError)
  =>
    SendErrorNotConnected

  fun ref close(conn: TCPConnection ref) =>
    conn._set_state(_UnconnectedClosing)

  fun ref hard_close(conn: TCPConnection ref,
    cause: _HardCloseCause)
  =>
    conn._hard_close_connecting(cause)

  fun ref start_tls(conn: TCPConnection ref, ssl_ctx: SSLContext val,
    host: String): (None | StartTLSError)
  =>
    StartTLSNotConnected

  fun ref read_again(conn: TCPConnection ref) =>
    None

  fun ref ssl_handshake_complete(conn: TCPConnection ref,
    s: EitherLifecycleEventReceiver ref)
  =>
    _Unreachable()

  fun keepalive(conn: TCPConnection box, secs: U32) => None

  fun getsockopt(conn: TCPConnection box, level: I32, option_name: I32,
    option_max_size: USize): (U32, Array[U8] iso^)
  =>
    (1, recover Array[U8] end)

  fun getsockopt_u32(conn: TCPConnection box, level: I32,
    option_name: I32): (U32, U32)
  =>
    (1, 0)

  fun setsockopt(conn: TCPConnection box, level: I32, option_name: I32,
    option: Array[U8]): U32
  =>
    1

  fun setsockopt_u32(conn: TCPConnection box, level: I32, option_name: I32,
    option: U32): U32
  =>
    1

  fun ref idle_timeout(conn: TCPConnection ref,
    duration: (IdleTimeout | None))
  =>
    conn._store_idle_timeout(duration)

  fun ref set_timer(conn: TCPConnection ref,
    duration: TimerDuration): (TimerToken | SetTimerError)
  =>
    SetTimerNotOpen

  fun is_open(): Bool => false
  fun is_closed(): Bool => false
  fun sends_allowed(): Bool => false
  fun is_live(): Bool => false

  fun receive(event: AsioEventID, buffer: Pointer[U8] tag,
    size: USize): (SocketResult, USize)
  =>
    _Unreachable()
    (SocketResultError, 0)

class _Open is _ConnectionState
  fun ref own_event(conn: TCPConnection ref, flags: U32) =>
    conn._dispatch_io_event(flags)

  fun ref foreign_event(conn: TCPConnection ref, event: AsioEventID,
    flags: U32)
  =>
    // Removing this guard causes the test suite to hang.
    if PonyAsio.get_disposable(event) then return end
    if not (AsioEvent.errored(flags) or AsioEvent.writeable(flags)
      or AsioEvent.readable(flags))
    then
      return
    end

    // Happy Eyeballs straggler — clean up
    conn._decrement_inflight()
    conn._straggler_cleanup(event)

  fun ref send(conn: TCPConnection ref,
    data: (ByteSeq | ByteSeqIter)): (SendToken | SendError)
  =>
    conn._do_send(data)

  fun ref close(conn: TCPConnection ref) =>
    conn._set_state(_Closing)
    conn._initiate_shutdown()

  fun ref hard_close(conn: TCPConnection ref,
    cause: _HardCloseCause)
  =>
    conn._hard_close_connected()

  fun ref start_tls(conn: TCPConnection ref, ssl_ctx: SSLContext val,
    host: String): (None | StartTLSError)
  =>
    conn._do_start_tls(ssl_ctx, host)

  fun ref read_again(conn: TCPConnection ref) =>
    conn._do_read_again()

  fun ref ssl_handshake_complete(conn: TCPConnection ref,
    s: EitherLifecycleEventReceiver ref)
  =>
    // Already open: the handshake completed on the way in.
    None

  fun keepalive(conn: TCPConnection box, secs: U32) =>
    conn._do_keepalive(secs)

  fun getsockopt(conn: TCPConnection box, level: I32, option_name: I32,
    option_max_size: USize): (U32, Array[U8] iso^)
  =>
    conn._do_getsockopt(level, option_name, option_max_size)

  fun getsockopt_u32(conn: TCPConnection box, level: I32,
    option_name: I32): (U32, U32)
  =>
    conn._do_getsockopt_u32(level, option_name)

  fun setsockopt(conn: TCPConnection box, level: I32, option_name: I32,
    option: Array[U8]): U32
  =>
    conn._do_setsockopt(level, option_name, option)

  fun setsockopt_u32(conn: TCPConnection box, level: I32, option_name: I32,
    option: U32): U32
  =>
    conn._do_setsockopt_u32(level, option_name, option)

  fun ref idle_timeout(conn: TCPConnection ref,
    duration: (IdleTimeout | None))
  =>
    conn._do_idle_timeout(duration)

  fun ref set_timer(conn: TCPConnection ref,
    duration: TimerDuration): (TimerToken | SetTimerError)
  =>
    conn._do_set_timer(duration)

  fun is_open(): Bool => true
  fun is_closed(): Bool => false
  fun sends_allowed(): Bool => true
  fun is_live(): Bool => true

  fun receive(event: AsioEventID, buffer: Pointer[U8] tag,
    size: USize): (SocketResult, USize)
  =>
    PonyTCP.receive(event, buffer, size)

class _Closing is _ConnectionState
  fun ref own_event(conn: TCPConnection ref, flags: U32) =>
    conn._dispatch_io_event(flags)

  fun ref foreign_event(conn: TCPConnection ref, event: AsioEventID,
    flags: U32)
  =>
    // Removing this guard causes the test suite to hang.
    if PonyAsio.get_disposable(event) then return end
    if not (AsioEvent.errored(flags) or AsioEvent.writeable(flags)
      or AsioEvent.readable(flags))
    then
      return
    end

    // Happy Eyeballs straggler — clean up
    conn._decrement_inflight()
    conn._straggler_cleanup(event)

    // Inflight drained — can now send FIN
    conn._initiate_shutdown()
    conn._check_shutdown_complete()

  fun ref send(conn: TCPConnection ref,
    data: (ByteSeq | ByteSeqIter)): (SendToken | SendError)
  =>
    SendErrorNotConnected

  fun ref close(conn: TCPConnection ref) =>
    None

  fun ref hard_close(conn: TCPConnection ref,
    cause: _HardCloseCause)
  =>
    conn._hard_close_connected()

  fun ref start_tls(conn: TCPConnection ref, ssl_ctx: SSLContext val,
    host: String): (None | StartTLSError)
  =>
    StartTLSNotConnected

  fun ref read_again(conn: TCPConnection ref) =>
    conn._do_read_again()

  fun ref ssl_handshake_complete(conn: TCPConnection ref,
    s: EitherLifecycleEventReceiver ref)
  =>
    // Already open: the handshake completed on the way in.
    None

  fun keepalive(conn: TCPConnection box, secs: U32) => None

  fun getsockopt(conn: TCPConnection box, level: I32, option_name: I32,
    option_max_size: USize): (U32, Array[U8] iso^)
  =>
    (1, recover Array[U8] end)

  fun getsockopt_u32(conn: TCPConnection box, level: I32,
    option_name: I32): (U32, U32)
  =>
    (1, 0)

  fun setsockopt(conn: TCPConnection box, level: I32, option_name: I32,
    option: Array[U8]): U32
  =>
    1

  fun setsockopt_u32(conn: TCPConnection box, level: I32, option_name: I32,
    option: U32): U32
  =>
    1

  fun ref idle_timeout(conn: TCPConnection ref,
    duration: (IdleTimeout | None))
  =>
    conn._store_idle_timeout(duration)

  fun ref set_timer(conn: TCPConnection ref,
    duration: TimerDuration): (TimerToken | SetTimerError)
  =>
    SetTimerNotOpen

  fun is_open(): Bool => false
  fun is_closed(): Bool => true
  fun sends_allowed(): Bool => false
  fun is_live(): Bool => true

  fun receive(event: AsioEventID, buffer: Pointer[U8] tag,
    size: USize): (SocketResult, USize)
  =>
    PonyTCP.receive(event, buffer, size)

class _UnconnectedClosing is _ConnectionState
  """
  Draining inflight Happy Eyeballs connections after close() during the
  connecting phase. The failure callback is deferred until all inflight
  connections drain. hard_close() can interrupt this drain (e.g., connection
  timeout fires during drain), transitioning to _Closed immediately.
  """
  fun ref own_event(conn: TCPConnection ref, flags: U32) =>
    _Unreachable()

  fun ref foreign_event(conn: TCPConnection ref, event: AsioEventID,
    flags: U32)
  =>
    if not (AsioEvent.errored(flags) or AsioEvent.writeable(flags)
      or AsioEvent.readable(flags))
    then
      return
    end

    let remaining = conn._decrement_inflight()
    conn._straggler_cleanup(event)

    if remaining == 0 then
        conn._hard_close_connecting(_UnspecifiedCause)
    end

  fun ref send(conn: TCPConnection ref,
    data: (ByteSeq | ByteSeqIter)): (SendToken | SendError)
  =>
    SendErrorNotConnected

  fun ref close(conn: TCPConnection ref) =>
    None

  fun ref hard_close(conn: TCPConnection ref,
    cause: _HardCloseCause)
  =>
    conn._hard_close_connecting(cause)

  fun ref start_tls(conn: TCPConnection ref, ssl_ctx: SSLContext val,
    host: String): (None | StartTLSError)
  =>
    StartTLSNotConnected

  fun ref read_again(conn: TCPConnection ref) =>
    None

  fun ref ssl_handshake_complete(conn: TCPConnection ref,
    s: EitherLifecycleEventReceiver ref)
  =>
    _Unreachable()

  fun keepalive(conn: TCPConnection box, secs: U32) => None

  fun getsockopt(conn: TCPConnection box, level: I32, option_name: I32,
    option_max_size: USize): (U32, Array[U8] iso^)
  =>
    (1, recover Array[U8] end)

  fun getsockopt_u32(conn: TCPConnection box, level: I32,
    option_name: I32): (U32, U32)
  =>
    (1, 0)

  fun setsockopt(conn: TCPConnection box, level: I32, option_name: I32,
    option: Array[U8]): U32
  =>
    1

  fun setsockopt_u32(conn: TCPConnection box, level: I32, option_name: I32,
    option: U32): U32
  =>
    1

  fun ref idle_timeout(conn: TCPConnection ref,
    duration: (IdleTimeout | None))
  =>
    conn._store_idle_timeout(duration)

  fun ref set_timer(conn: TCPConnection ref,
    duration: TimerDuration): (TimerToken | SetTimerError)
  =>
    SetTimerNotOpen

  fun is_open(): Bool => false
  fun is_closed(): Bool => true
  fun sends_allowed(): Bool => false
  fun is_live(): Bool => false

  fun receive(event: AsioEventID, buffer: Pointer[U8] tag,
    size: USize): (SocketResult, USize)
  =>
    _Unreachable()
    (SocketResultError, 0)

class _Closed is _ConnectionState
  fun ref own_event(conn: TCPConnection ref, flags: U32) =>
    None

  fun ref foreign_event(conn: TCPConnection ref, event: AsioEventID,
    flags: U32)
  =>
    if not (AsioEvent.errored(flags) or AsioEvent.writeable(flags)
      or AsioEvent.readable(flags))
    then
      return
    end

    // Happy Eyeballs straggler — clean up
    conn._decrement_inflight()
    conn._straggler_cleanup(event)

  fun ref send(conn: TCPConnection ref,
    data: (ByteSeq | ByteSeqIter)): (SendToken | SendError)
  =>
    SendErrorNotConnected

  fun ref close(conn: TCPConnection ref) =>
    None

  fun ref hard_close(conn: TCPConnection ref,
    cause: _HardCloseCause)
  =>
    None

  fun ref start_tls(conn: TCPConnection ref, ssl_ctx: SSLContext val,
    host: String): (None | StartTLSError)
  =>
    StartTLSNotConnected

  fun ref read_again(conn: TCPConnection ref) =>
    None

  fun ref ssl_handshake_complete(conn: TCPConnection ref,
    s: EitherLifecycleEventReceiver ref)
  =>
    _Unreachable()

  fun keepalive(conn: TCPConnection box, secs: U32) => None

  fun getsockopt(conn: TCPConnection box, level: I32, option_name: I32,
    option_max_size: USize): (U32, Array[U8] iso^)
  =>
    (1, recover Array[U8] end)

  fun getsockopt_u32(conn: TCPConnection box, level: I32,
    option_name: I32): (U32, U32)
  =>
    (1, 0)

  fun setsockopt(conn: TCPConnection box, level: I32, option_name: I32,
    option: Array[U8]): U32
  =>
    1

  fun setsockopt_u32(conn: TCPConnection box, level: I32, option_name: I32,
    option: U32): U32
  =>
    1

  fun ref idle_timeout(conn: TCPConnection ref,
    duration: (IdleTimeout | None))
  =>
    conn._store_idle_timeout(duration)

  fun ref set_timer(conn: TCPConnection ref,
    duration: TimerDuration): (TimerToken | SetTimerError)
  =>
    SetTimerNotOpen

  fun is_open(): Bool => false
  fun is_closed(): Bool => true
  fun sends_allowed(): Bool => false
  fun is_live(): Bool => false

  fun receive(event: AsioEventID, buffer: Pointer[U8] tag,
    size: USize): (SocketResult, USize)
  =>
    _Unreachable()
    (SocketResultError, 0)

class _SSLHandshaking is _ConnectionState
  """
  TCP connected, initial SSL handshake in progress. The application has not
  been notified yet — `_on_connected`/`_on_started` fires only after the
  handshake completes.
  """
  fun ref own_event(conn: TCPConnection ref, flags: U32) =>
    conn._dispatch_io_event(flags)

  fun ref foreign_event(conn: TCPConnection ref, event: AsioEventID,
    flags: U32)
  =>
    // Removing this guard causes the test suite to hang.
    if PonyAsio.get_disposable(event) then return end
    if not (AsioEvent.errored(flags) or AsioEvent.writeable(flags)
      or AsioEvent.readable(flags))
    then
      return
    end

    // Happy Eyeballs straggler — clean up
    conn._decrement_inflight()
    conn._straggler_cleanup(event)

  fun ref send(conn: TCPConnection ref,
    data: (ByteSeq | ByteSeqIter)): (SendToken | SendError)
  =>
    SendErrorNotConnected

  fun ref close(conn: TCPConnection ref) =>
    // Can't drain gracefully during handshake — nothing to FIN.
    conn.hard_close()

  fun ref hard_close(conn: TCPConnection ref,
    cause: _HardCloseCause)
  =>
    conn._hard_close_ssl_handshaking(cause)

  fun ref start_tls(conn: TCPConnection ref, ssl_ctx: SSLContext val,
    host: String): (None | StartTLSError)
  =>
    StartTLSNotConnected

  fun ref read_again(conn: TCPConnection ref) =>
    conn._do_read_again()

  fun ref ssl_handshake_complete(conn: TCPConnection ref,
    s: EitherLifecycleEventReceiver ref)
  =>
    conn._set_state(_Open)
    conn._cancel_connect_timer()
    conn._arm_idle_timer()
    match \exhaustive\ s
    | let c: ClientLifecycleEventReceiver ref =>
      c._on_connected()
    | let srv: ServerLifecycleEventReceiver ref =>
      srv._on_started()
    end

  fun keepalive(conn: TCPConnection box, secs: U32) => None

  fun getsockopt(conn: TCPConnection box, level: I32, option_name: I32,
    option_max_size: USize): (U32, Array[U8] iso^)
  =>
    (1, recover Array[U8] end)

  fun getsockopt_u32(conn: TCPConnection box, level: I32,
    option_name: I32): (U32, U32)
  =>
    (1, 0)

  fun setsockopt(conn: TCPConnection box, level: I32, option_name: I32,
    option: Array[U8]): U32
  =>
    1

  fun setsockopt_u32(conn: TCPConnection box, level: I32, option_name: I32,
    option: U32): U32
  =>
    1

  fun ref idle_timeout(conn: TCPConnection ref,
    duration: (IdleTimeout | None))
  =>
    conn._store_idle_timeout(duration)

  fun ref set_timer(conn: TCPConnection ref,
    duration: TimerDuration): (TimerToken | SetTimerError)
  =>
    SetTimerNotOpen

  fun is_open(): Bool => false
  fun is_closed(): Bool => false
  fun sends_allowed(): Bool => false
  fun is_live(): Bool => true

  fun receive(event: AsioEventID, buffer: Pointer[U8] tag,
    size: USize): (SocketResult, USize)
  =>
    PonyTCP.receive(event, buffer, size)

class _TLSUpgrading is _ConnectionState
  """
  Established connection upgrading to TLS via `start_tls()`. The application
  has already been notified of the plaintext connection — `_on_tls_ready`
  fires when the handshake completes.
  """
  fun ref own_event(conn: TCPConnection ref, flags: U32) =>
    conn._dispatch_io_event(flags)

  fun ref foreign_event(conn: TCPConnection ref, event: AsioEventID,
    flags: U32)
  =>
    // Removing this guard causes the test suite to hang.
    if PonyAsio.get_disposable(event) then return end
    if not (AsioEvent.errored(flags) or AsioEvent.writeable(flags)
      or AsioEvent.readable(flags))
    then
      return
    end

    // Happy Eyeballs straggler — clean up
    conn._decrement_inflight()
    conn._straggler_cleanup(event)

  fun ref send(conn: TCPConnection ref,
    data: (ByteSeq | ByteSeqIter)): (SendToken | SendError)
  =>
    SendErrorNotConnected

  fun ref close(conn: TCPConnection ref) =>
    // Can't send FIN during TLS handshake.
    conn.hard_close()

  fun ref hard_close(conn: TCPConnection ref,
    cause: _HardCloseCause)
  =>
    conn._hard_close_tls_upgrading(cause)

  fun ref start_tls(conn: TCPConnection ref, ssl_ctx: SSLContext val,
    host: String): (None | StartTLSError)
  =>
    StartTLSAlreadyTLS

  fun ref read_again(conn: TCPConnection ref) =>
    conn._do_read_again()

  fun ref ssl_handshake_complete(conn: TCPConnection ref,
    s: EitherLifecycleEventReceiver ref)
  =>
    // TLS upgrade handshake complete — no timer arm needed (timer is
    // already running from the plaintext phase).
    conn._set_state(_Open)
    s._on_tls_ready()

  fun keepalive(conn: TCPConnection box, secs: U32) =>
    conn._do_keepalive(secs)

  fun getsockopt(conn: TCPConnection box, level: I32, option_name: I32,
    option_max_size: USize): (U32, Array[U8] iso^)
  =>
    conn._do_getsockopt(level, option_name, option_max_size)

  fun getsockopt_u32(conn: TCPConnection box, level: I32,
    option_name: I32): (U32, U32)
  =>
    conn._do_getsockopt_u32(level, option_name)

  fun setsockopt(conn: TCPConnection box, level: I32, option_name: I32,
    option: Array[U8]): U32
  =>
    conn._do_setsockopt(level, option_name, option)

  fun setsockopt_u32(conn: TCPConnection box, level: I32, option_name: I32,
    option: U32): U32
  =>
    conn._do_setsockopt_u32(level, option_name, option)

  fun ref idle_timeout(conn: TCPConnection ref,
    duration: (IdleTimeout | None))
  =>
    conn._do_idle_timeout(duration)

  fun ref set_timer(conn: TCPConnection ref,
    duration: TimerDuration): (TimerToken | SetTimerError)
  =>
    conn._do_set_timer(duration)

  fun is_open(): Bool => true
  fun is_closed(): Bool => false
  fun sends_allowed(): Bool => false
  fun is_live(): Bool => true

  fun receive(event: AsioEventID, buffer: Pointer[U8] tag,
    size: USize): (SocketResult, USize)
  =>
    PonyTCP.receive(event, buffer, size)
