actor _LegacyServerConnection is
  (TCPConnectionActor & ServerLifecycleEventReceiver & _LegacyConnection)
  """
  A server-side accepted connection, created by `LegacyTCPListener`. Not
  created directly by applications. Presents the `LegacyTCPConnection` surface
  to the notifier the listener supplied.
  """
  var _conn: TCPConnection = TCPConnection.none()
  var _notify: LegacyTCPConnectionNotify
  var _in_sent: Bool = false
  var _rbs: USize
  embed _read: _LegacyReadState

  new _accept(
    auth: TCPServerAuth,
    notify: LegacyTCPConnectionNotify iso,
    fd: U32,
    read_buffer_size: USize = 16384,
    yield_after_reading: USize = 16384)
  =>
    """
    Take ownership of an accepted socket `fd`.
    """
    _notify = consume notify
    _rbs = _LegacyReadBufferSize(read_buffer_size)()
    _read = _LegacyReadState(yield_after_reading)
    _conn =
      TCPConnection.server(
        auth, fd, this, this, _LegacyReadBufferSize(read_buffer_size))

  fun ref _connection(): TCPConnection =>
    _conn

  fun ref _notifier(): LegacyTCPConnectionNotify =>
    _notify

  fun ref _set_notifier(notify: LegacyTCPConnectionNotify) =>
    _notify = notify

  fun ref _sending(): Bool =>
    _in_sent

  fun ref _set_sending(value: Bool) =>
    _in_sent = value

  fun ref _read_buffer_size(): USize =>
    _rbs

  fun ref _read_state(): _LegacyReadState =>
    _read

  be dispose() =>
    """
    Gracefully close the connection once queued writes are sent, matching the
    stdlib `net.TCPConnection.dispose`. A muted connection hard closes and drops
    data instead (see `close`). This overrides lori's own
    `TCPConnectionActor.dispose`, which hard closes to sidestep the
    edge-triggered race in issue #229; the Legacy API keeps the stdlib's
    graceful behavior.
    """
    _conn.close()

  fun ref _on_started() =>
    _notify.accepted(this)

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    _deliver_received(consume data)

  fun ref _on_closed() =>
    _notify.closed(this)

  fun ref _on_throttled() =>
    _notify.throttled(this)

  fun ref _on_unthrottled() =>
    _notify.unthrottled(this)
