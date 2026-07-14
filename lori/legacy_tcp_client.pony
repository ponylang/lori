actor LegacyTCPClient is
  (TCPConnectionActor & ClientLifecycleEventReceiver & _LegacyConnection)
  """
  A client-side TCP connection with the standard library `net` package's
  `TCPConnection` API, built on lori. Create one to connect to a server:

  ```pony
  LegacyTCPClient(TCPConnectAuth(env.root), MyNotify, "", "8989")
  ```

  Data arrives at the `received` method of the `LegacyTCPConnectionNotify` you
  supply. See `LegacyTCPConnection` for the connection methods.
  """
  var _conn: TCPConnection = TCPConnection.none()
  var _notify: LegacyTCPConnectionNotify
  var _in_sent: Bool = false
  var _rbs: USize
  embed _read: _LegacyReadState

  new create(
    auth: TCPConnectAuth,
    notify: LegacyTCPConnectionNotify iso,
    host: String,
    service: String,
    from: String = "",
    read_buffer_size: USize = 16384,
    yield_after_reading: USize = 16384,
    yield_after_writing: USize = 16384)
  =>
    """
    Connect via IPv4 or IPv6. If `from` is non-empty, connect from that
    interface. `yield_after_writing` is accepted for source compatibility but
    has no effect (see the package documentation).
    """
    _notify = consume notify
    _rbs = _LegacyReadBufferSize(read_buffer_size)()
    _read = _LegacyReadState(yield_after_reading)
    (let host', let service') = _notify.proxy_via(host, service)
    _conn =
      TCPConnection.client(
        auth,
        host',
        service',
        from,
        this,
        this,
        _LegacyReadBufferSize(read_buffer_size),
        DualStack)

  new ip4(
    auth: TCPConnectAuth,
    notify: LegacyTCPConnectionNotify iso,
    host: String,
    service: String,
    from: String = "",
    read_buffer_size: USize = 16384,
    yield_after_reading: USize = 16384,
    yield_after_writing: USize = 16384)
  =>
    """
    Connect via IPv4.
    """
    _notify = consume notify
    _rbs = _LegacyReadBufferSize(read_buffer_size)()
    _read = _LegacyReadState(yield_after_reading)
    (let host', let service') = _notify.proxy_via(host, service)
    _conn =
      TCPConnection.client(
        auth,
        host',
        service',
        from,
        this,
        this,
        _LegacyReadBufferSize(read_buffer_size),
        IP4)

  new ip6(
    auth: TCPConnectAuth,
    notify: LegacyTCPConnectionNotify iso,
    host: String,
    service: String,
    from: String = "",
    read_buffer_size: USize = 16384,
    yield_after_reading: USize = 16384,
    yield_after_writing: USize = 16384)
  =>
    """
    Connect via IPv6.
    """
    _notify = consume notify
    _rbs = _LegacyReadBufferSize(read_buffer_size)()
    _read = _LegacyReadState(yield_after_reading)
    (let host', let service') = _notify.proxy_via(host, service)
    _conn =
      TCPConnection.client(
        auth,
        host',
        service',
        from,
        this,
        this,
        _LegacyReadBufferSize(read_buffer_size),
        IP6)

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

  fun ref _on_connecting(inflight_connections: U32) =>
    _notify.connecting(this, inflight_connections)

  fun ref _on_connected() =>
    _notify.connected(this)

  fun ref _on_connection_failure(reason: ConnectionFailureReason) =>
    _notify.connect_failed(this)

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    _deliver_received(consume data)

  fun ref _on_closed() =>
    _notify.closed(this)

  fun ref _on_throttled() =>
    _notify.throttled(this)

  fun ref _on_unthrottled() =>
    _notify.unthrottled(this)
