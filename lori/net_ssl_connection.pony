use "collections"
use "net_ssl"

class NetSSLClientConnection is ClientLifecycleEventReceiver
  let _ssl: SSL
  let _lifecycle_event_receiver: ClientLifecycleEventReceiver
  let _pending: List[ByteSeq] = _pending.create()
  var _connected: Bool = false
  var _closed: Bool = false
  var _expect: USize = 0

  new create(ssl: SSL iso,
    lifecycle_event_receiver: ClientLifecycleEventReceiver)
  =>
    _ssl = consume ssl
    _lifecycle_event_receiver = lifecycle_event_receiver

  fun ref _connection(): TCPConnection =>
    _lifecycle_event_receiver._connection()

  fun ref _next_lifecycle_event_receiver(): (ClientLifecycleEventReceiver | None) =>
    _lifecycle_event_receiver

  fun ref on_connected() =>
    """
    Swallow this event until the handshake is complete.
    """

    _ssl_poll()

  fun ref on_connection_failure() =>
    _lifecycle_event_receiver.on_connection_failure()

  fun ref on_closed() =>
    """
    Clean up our SSL session and inform the wrapped protocol that the connection
    closing.
    """
    _closed = true
    _ssl_poll()
    _ssl.dispose()
    _connected = false
    _pending.clear()

    _lifecycle_event_receiver.on_closed()

  fun ref on_expect_set(qty: USize): USize =>
    """
    Keep track of the expect count for the wrapped protocol. Always tell the
    TCPConnection to read all available data.
    """
    _expect = _lifecycle_event_receiver.on_expect_set(qty)
    0

  fun ref on_received(data: Array[U8] iso) =>
    """
    Pass the data to the SSL session and check for both new application data
    and new destination data.
    """

    _ssl.receive(consume data)
    _ssl_poll()

  fun ref on_send(data: ByteSeq): (ByteSeq | None) =>
    """
    Pass the data to the SSL session and check for both new application data
    and new destination data.
    """

    match _lifecycle_event_receiver.on_send(data)
    | let d: ByteSeq =>
      if _connected then
        try
          _ssl.write(d)?
        else
          return None
        end
      else
        _pending.push(d)
      end
    end
    _ssl_poll()

  fun ref on_throttled() =>
    _lifecycle_event_receiver.on_throttled()

  fun ref on_unthrottled() =>
    _lifecycle_event_receiver.on_unthrottled()

  fun ref _ssl_poll() =>
    """
    Checks for both new application data and new destination data. Informs the
    wrapped protocol that is has connected when the handshake is complete.
    """
    match _ssl.state()
    | SSLReady =>
      // TODO ALPNProtocolNotify is not implemented
      if not _connected then
        _connected = true
        _lifecycle_event_receiver.on_connected()
      end

      if not _connected then
        try
          while _pending.size() > 0 do
            _ssl.write(_pending.shift()?)?
          end
        end
      end
    | SSLAuthFail =>
      // TODO we probably need some indicator of failure means
      if not _closed then
        _lifecycle_event_receiver._connection().close()
      end

      return
    | SSLError =>
      // TODO we probably need some indicator of failure means
      if not _closed then
        _lifecycle_event_receiver._connection().close()
      end

      return
    end

    while true do
      match _ssl.read(_expect)
      | let data: Array[U8] iso =>
        _lifecycle_event_receiver.on_received(consume data)
      | None =>
        break
      end
    end

    try
      while _ssl.can_send() do
        _lifecycle_event_receiver._connection()._send_final(_ssl.send()?)
      end
    end

class NetSSLServerConnection is ServerLifecycleEventReceiver
  let _ssl: SSL
  let _lifecycle_event_receiver: ServerLifecycleEventReceiver
  let _pending: List[ByteSeq] = _pending.create()
  var _connected: Bool = false
  var _closed: Bool = false
  var _expect: USize = 0

  new create(ssl: SSL iso,
    lifecycle_event_receiver: ServerLifecycleEventReceiver)
  =>
    _ssl = consume ssl
    _lifecycle_event_receiver = lifecycle_event_receiver

  fun ref _connection(): TCPConnection =>
    _lifecycle_event_receiver._connection()

  fun ref _next_lifecycle_event_receiver(): (ServerLifecycleEventReceiver | None) =>
    _lifecycle_event_receiver

  fun ref on_started() =>
    """
    Swallow this event until the handshake is complete.
    """

    _ssl_poll()

  fun ref on_closed() =>
    """
    Clean up our SSL session and inform the wrapped protocol that the connection
    closing.
    """

    _closed = true
    _ssl_poll()
    _ssl.dispose()
    _connected = false
    _pending.clear()

    _lifecycle_event_receiver.on_closed()

  fun ref on_expect_set(qty: USize): USize =>
    """
    Keep track of the expect count for the wrapped protocol. Always tell the
    TCPConnection to read all available data.
    """
    _expect = _lifecycle_event_receiver.on_expect_set(qty)
    0

  fun ref on_received(data: Array[U8] iso) =>
    """
    Pass the data to the SSL session and check for both new application data
    and new destination data.
    """

    _ssl.receive(consume data)
    _ssl_poll()

  fun ref on_send(data: ByteSeq): (ByteSeq | None) =>
    """
    Pass the data to the SSL session and check for both new application data
    and new destination data.
    """

    match _lifecycle_event_receiver.on_send(data)
    | let d: ByteSeq =>
      if _connected then
        try
          _ssl.write(d)?
        else
          return None
        end
      else
        _pending.push(d)
      end
    end
    _ssl_poll()

  fun ref on_throttled() =>
    _lifecycle_event_receiver.on_throttled()

  fun ref on_unthrottled() =>
    _lifecycle_event_receiver.on_unthrottled()

  fun ref _ssl_poll() =>
    """
    Checks for both new application data and new destination data. Informs the
    wrapped protocol that is has connected when the handshake is complete.
    """
    match _ssl.state()
    | SSLReady =>
      // TODO ALPNProtocolNotify is not implemented
      if not _connected then
        _connected = true
        _lifecycle_event_receiver.on_started()
      end

      if not _connected then
        try
          while _pending.size() > 0 do
            _ssl.write(_pending.shift()?)?
          end
        end
      end
    | SSLAuthFail =>
      // TODO we probably need some indicator of failure means
      if not _closed then
        _lifecycle_event_receiver._connection().close()
      end

      return
    | SSLError =>
      // TODO we probably need some indicator of failure means
      if not _closed then
        _lifecycle_event_receiver._connection().close()
      end

      return
    end

    while true do
      match _ssl.read(_expect)
      | let data: Array[U8] iso =>
        _lifecycle_event_receiver.on_received(consume data)
      | None =>
        break
      end
    end

    try
      while _ssl.can_send() do
        _lifecycle_event_receiver._connection()._send_final(_ssl.send()?)
      end
    end
