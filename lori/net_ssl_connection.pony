use "ssl/net"

interface NetSSLLifecycleEventReceiver
  """
  Callbacks for major SSL lifecycle changes. Implement this interface
  and pass it to SSLClientInterceptor or SSLServerInterceptor to receive
  SSL-specific notifications.
  """
  fun ref on_alpn_negotiated(protocol: (String | None)) =>
    """
    Called when a final protocol is negotiated using ALPN. Will only be
    called if you set your connection up using ALPN.
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

class SSLClientInterceptor is DataInterceptor
  """
  DataInterceptor that adds SSL/TLS encryption for client connections.

  Handles the SSL handshake during the setup phase, defers signaling
  ready until the handshake completes, and encrypts/decrypts data
  flowing through the connection.
  """
  let _ssl: SSL
  let _ssl_receiver: (NetSSLLifecycleEventReceiver ref | None)
  var _connected: Bool = false
  var _closed: Bool = false
  var _expect: USize = 0
  var _control: (InterceptorControl ref | None) = None

  new create(ssl: SSL iso,
    ssl_receiver: (NetSSLLifecycleEventReceiver ref | None) = None)
  =>
    _ssl = consume ssl
    _ssl_receiver = ssl_receiver

  fun ref on_setup(control: InterceptorControl ref) =>
    _control = control
    // Flush any initial SSL protocol data. For clients, this sends
    // the ClientHello to initiate the handshake.
    try
      while _ssl.can_send() do
        control.send_to_wire(_ssl.send()?)
      end
    end

  fun ref on_teardown() =>
    _closed = true
    _ssl.dispose()
    _connected = false
    _control = None

  fun ref incoming(data: Array[U8] iso,
    receiver: IncomingDataReceiver ref,
    wire: WireSender ref)
  =>
    _ssl.receive(consume data)
    _ssl_poll(receiver, wire)

  fun ref outgoing(data: ByteSeq, wire: WireSender ref) =>
    try _ssl.write(data)? end
    try
      while _ssl.can_send() do
        wire.send(_ssl.send()?)
      end
    end

  fun ref adjust_expect(qty: USize): USize =>
    _expect = qty
    0

  fun ref _ssl_poll(receiver: IncomingDataReceiver ref,
    wire: WireSender ref)
  =>
    match _ssl.state()
    | SSLReady =>
      if not _connected then
        _connected = true
        match _control
        | let c: InterceptorControl ref => c.signal_ready()
        end

        match _ssl_receiver
        | let ler: NetSSLLifecycleEventReceiver ref =>
          ler.on_alpn_negotiated(_ssl.alpn_selected())
        end
      end
    | SSLAuthFail =>
      if not _closed then
        match _ssl_receiver
        | let ler: NetSSLLifecycleEventReceiver ref =>
          ler.on_ssl_auth_failed()
        end
        match _control
        | let c: InterceptorControl ref => c.close()
        end
      end
      return
    | SSLError =>
      if not _closed then
        match _ssl_receiver
        | let ler: NetSSLLifecycleEventReceiver ref =>
          ler.on_ssl_error()
        end
        match _control
        | let c: InterceptorControl ref => c.close()
        end
      end
      return
    end

    while true do
      match _ssl.read(_expect)
      | let d: Array[U8] iso => receiver.receive(consume d)
      | None => break
      end
    end

    try
      while _ssl.can_send() do
        wire.send(_ssl.send()?)
      end
    end

class SSLServerInterceptor is DataInterceptor
  """
  DataInterceptor that adds SSL/TLS encryption for server connections.

  Identical to SSLClientInterceptor in behavior. The separation exists
  because SSL client and server roles differ at the protocol level (who
  initiates the handshake), handled internally by the SSL library.
  """
  let _ssl: SSL
  let _ssl_receiver: (NetSSLLifecycleEventReceiver ref | None)
  var _connected: Bool = false
  var _closed: Bool = false
  var _expect: USize = 0
  var _control: (InterceptorControl ref | None) = None

  new create(ssl: SSL iso,
    ssl_receiver: (NetSSLLifecycleEventReceiver ref | None) = None)
  =>
    _ssl = consume ssl
    _ssl_receiver = ssl_receiver

  fun ref on_setup(control: InterceptorControl ref) =>
    _control = control
    // Flush any initial SSL protocol data. For servers this is typically
    // a no-op since the server waits for ClientHello, but included for
    // consistency with SSLClientInterceptor.
    try
      while _ssl.can_send() do
        control.send_to_wire(_ssl.send()?)
      end
    end

  fun ref on_teardown() =>
    _closed = true
    _ssl.dispose()
    _connected = false
    _control = None

  fun ref incoming(data: Array[U8] iso,
    receiver: IncomingDataReceiver ref,
    wire: WireSender ref)
  =>
    _ssl.receive(consume data)
    _ssl_poll(receiver, wire)

  fun ref outgoing(data: ByteSeq, wire: WireSender ref) =>
    try _ssl.write(data)? end
    try
      while _ssl.can_send() do
        wire.send(_ssl.send()?)
      end
    end

  fun ref adjust_expect(qty: USize): USize =>
    _expect = qty
    0

  fun ref _ssl_poll(receiver: IncomingDataReceiver ref,
    wire: WireSender ref)
  =>
    match _ssl.state()
    | SSLReady =>
      if not _connected then
        _connected = true
        match _control
        | let c: InterceptorControl ref => c.signal_ready()
        end

        match _ssl_receiver
        | let ler: NetSSLLifecycleEventReceiver ref =>
          ler.on_alpn_negotiated(_ssl.alpn_selected())
        end
      end
    | SSLAuthFail =>
      if not _closed then
        match _ssl_receiver
        | let ler: NetSSLLifecycleEventReceiver ref =>
          ler.on_ssl_auth_failed()
        end
        match _control
        | let c: InterceptorControl ref => c.close()
        end
      end
      return
    | SSLError =>
      if not _closed then
        match _ssl_receiver
        | let ler: NetSSLLifecycleEventReceiver ref =>
          ler.on_ssl_error()
        end
        match _control
        | let c: InterceptorControl ref => c.close()
        end
      end
      return
    end

    while true do
      match _ssl.read(_expect)
      | let d: Array[U8] iso => receiver.receive(consume d)
      | None => break
      end
    end

    try
      while _ssl.can_send() do
        wire.send(_ssl.send()?)
      end
    end
