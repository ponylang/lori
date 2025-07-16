use "collections"
use "ssl/net"

interface NetSSLLifecycleEventReceiver
  """
  If you implement this interface, you will be able to get callbackes when major
  SSL lifecycle changes happen if you are using a `NetSSLClientConnection` or
  `NetSSLClientConnection.
  """
  fun ref on_alpn_negotiated(protocol: (String | None)) =>
    """
    Called when a final protocol is negotatiated using ALPN. Will only be
    called if you set your connnection up using ALPN.
    """
    None

  fun ref on_ssl_auth_failed() =>
    """
    Called when the SSL handshake fails due to authentication failure.
    """
    None

  fun ref on_ssl_error() =>
    """
    Called when an unknown SSL error was encountered during the handshake.
    """
    None

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

  fun ref _next_lifecycle_event_receiver(): ClientLifecycleEventReceiver =>
    _lifecycle_event_receiver

  fun ref _on_connected() =>
    """
    Swallow this event until the handshake is complete.
    """

    _ssl_poll()

  fun ref _on_connection_failure() =>
    _lifecycle_event_receiver._on_connection_failure()

  fun ref _on_closed() =>
    """
    Clean up our SSL session and inform the wrapped protocol that the connection
    closing.
    """
    _closed = true
    _ssl_poll()
    _ssl.dispose()
    _connected = false
    _pending.clear()

    _lifecycle_event_receiver._on_closed()

  fun ref _on_expect_set(qty: USize): USize =>
    """
    Keep track of the expect count for the wrapped protocol. Always tell the
    TCPConnection to read all available data.
    """
    _expect = _lifecycle_event_receiver._on_expect_set(qty)
    0

  fun ref _on_received(data: Array[U8] iso) =>
    """
    Pass the data to the SSL session and check for both new application data
    and new destination data.
    """

    _ssl.receive(consume data)
    _ssl_poll()

  fun ref _on_send(data: ByteSeq): (ByteSeq | None) =>
    """
    Pass the data to the SSL session and check for both new application data
    and new destination data.
    """

    match _lifecycle_event_receiver._on_send(data)
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

  fun ref _on_throttled() =>
    _lifecycle_event_receiver._on_throttled()

  fun ref _on_unthrottled() =>
    _lifecycle_event_receiver._on_unthrottled()

  fun ref _ssl_poll() =>
    """
    Checks for both new application data and new destination data. Informs the
    wrapped protocol that is has connected when the handshake is complete.
    """
    match _ssl.state()
    | SSLReady =>
      if not _connected then
        _connected = true
        _lifecycle_event_receiver._on_connected()

        match _lifecycle_event_receiver
        | let ler: NetSSLLifecycleEventReceiver =>
          ler.on_alpn_negotiated(_ssl.alpn_selected())
        end

        try
          while _pending.size() > 0 do
            _ssl.write(_pending.shift()?)?
          end
        end
      end
    | SSLAuthFail =>
      if not _closed then
        match _lifecycle_event_receiver
        | let ler: NetSSLLifecycleEventReceiver =>
          ler.on_ssl_auth_failed()
        end

        _lifecycle_event_receiver._connection().close()
      end

      return
    | SSLError =>
      if not _closed then
        match _lifecycle_event_receiver
        | let ler: NetSSLLifecycleEventReceiver =>
          ler.on_ssl_error()
        end

        _lifecycle_event_receiver._connection().close()
      end

      return
    end

    while true do
      match _ssl.read(_expect)
      | let data: Array[U8] iso =>
        _lifecycle_event_receiver._on_received(consume data)
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

  fun ref _next_lifecycle_event_receiver(): ServerLifecycleEventReceiver =>
    _lifecycle_event_receiver

  fun ref _on_started() =>
    """
    Swallow this event until the handshake is complete.
    """

    _ssl_poll()

  fun ref _on_closed() =>
    """
    Clean up our SSL session and inform the wrapped protocol that the connection
    closing.
    """

    _closed = true
    _ssl_poll()
    _ssl.dispose()
    _connected = false
    _pending.clear()

    _lifecycle_event_receiver._on_closed()

  fun ref _on_expect_set(qty: USize): USize =>
    """
    Keep track of the expect count for the wrapped protocol. Always tell the
    TCPConnection to read all available data.
    """
    _expect = _lifecycle_event_receiver._on_expect_set(qty)
    0

  fun ref _on_received(data: Array[U8] iso) =>
    """
    Pass the data to the SSL session and check for both new application data
    and new destination data.
    """

    _ssl.receive(consume data)
    _ssl_poll()

  fun ref _on_send(data: ByteSeq): (ByteSeq | None) =>
    """
    Pass the data to the SSL session and check for both new application data
    and new destination data.
    """

    match _lifecycle_event_receiver._on_send(data)
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

  fun ref _on_throttled() =>
    _lifecycle_event_receiver._on_throttled()

  fun ref _on_unthrottled() =>
    _lifecycle_event_receiver._on_unthrottled()

  fun ref _ssl_poll() =>
    """
    Checks for both new application data and new destination data. Informs the
    wrapped protocol that is has connected when the handshake is complete.
    """
    match _ssl.state()
    | SSLReady =>
      if not _connected then
        _connected = true
        _lifecycle_event_receiver._on_started()

        match _lifecycle_event_receiver
        | let ler: NetSSLLifecycleEventReceiver =>
          ler.on_alpn_negotiated(_ssl.alpn_selected())
        end

        try
          while _pending.size() > 0 do
            _ssl.write(_pending.shift()?)?
          end
        end
      end
    | SSLAuthFail =>
      if not _closed then
        match _lifecycle_event_receiver
        | let ler: NetSSLLifecycleEventReceiver =>
          ler.on_ssl_auth_failed()
        end

        _lifecycle_event_receiver._connection().close()
      end

      return
    | SSLError =>
      if not _closed then
        match _lifecycle_event_receiver
        | let ler: NetSSLLifecycleEventReceiver =>
          ler.on_ssl_error()
        end

        _lifecycle_event_receiver._connection().close()
      end

      return
    end

    while true do
      match _ssl.read(_expect)
      | let data: Array[U8] iso =>
        _lifecycle_event_receiver._on_received(consume data)
      | None =>
        break
      end
    end

    try
      while _ssl.can_send() do
        _lifecycle_event_receiver._connection()._send_final(_ssl.send()?)
      end
    end
