use "collections"
use net = "net"
use "ssl/net"

class TCPConnection
  var _connected: Bool = false
  var _closed: Bool = false
  var _shutdown: Bool = false
  var _shutdown_peer: Bool = false
  var _throttled: Bool = false
  var _readable: Bool = false
  var _writeable: Bool = false
  var _muted: Bool = false
  // Happy Eyeballs
  var _inflight_connections: U32 = 0

  var _fd: U32 = -1
  var _event: AsioEventID = AsioEvent.none()
  var _spawned_by: (TCPListenerActor | None) = None
  let _lifecycle_event_receiver: (ClientLifecycleEventReceiver ref | ServerLifecycleEventReceiver ref | None)
  let _enclosing: (TCPConnectionActor ref | None)
  let _pending: List[(ByteSeq, USize)] = _pending.create()
  var _read_buffer: Array[U8] iso = recover Array[U8] end
  var _bytes_in_read_buffer: USize = 0
  var _read_buffer_size: USize = 16384
  var _expect: USize = 0

  // Send token tracking
  var _next_token_id: USize = 0
  var _pending_token: (SendToken | None) = None

  // Built-in SSL support
  var _ssl: (SSL ref | None) = None
  var _ssl_ready: Bool = false
  var _ssl_failed: Bool = false
  var _ssl_expect: USize = 0
  // Distinguishes "initial SSL from constructor" vs "upgraded SSL from
  // start_tls()". Used by _ssl_poll() and hard_close() to route to the
  // correct callbacks (_on_tls_ready/_on_tls_failure vs
  // _on_connected/_on_started/_on_connection_failure/_on_start_failure).
  var _tls_upgrade: Bool = false

  // client startup state
  var _host: String = ""
  var _port: String = ""
  var _from: String = ""

  new client(auth: TCPConnectAuth,
    host: String,
    port: String,
    from: String,
    enclosing: TCPConnectionActor ref,
    ler: ClientLifecycleEventReceiver ref)
  =>
    _lifecycle_event_receiver = ler
    _enclosing = enclosing
    _host = host
    _port = port
    _from = from

    _resize_read_buffer_if_needed()

    enclosing._finish_initialization()

  new server(auth: TCPServerAuth,
    fd': U32,
    enclosing: TCPConnectionActor ref,
    ler: ServerLifecycleEventReceiver ref)
  =>
    _fd = fd'
    _lifecycle_event_receiver = ler
    _enclosing = enclosing

    _resize_read_buffer_if_needed()

    enclosing._finish_initialization()

  new ssl_client(auth: TCPConnectAuth,
    ssl_ctx: SSLContext val,
    host: String,
    port: String,
    from: String,
    enclosing: TCPConnectionActor ref,
    ler: ClientLifecycleEventReceiver ref)
  =>
    """
    Create a client-side SSL connection. The SSL session is created from the
    provided SSLContext. If session creation fails, the connection reports
    failure asynchronously via _on_connection_failure().
    """
    _lifecycle_event_receiver = ler
    _enclosing = enclosing
    _host = host
    _port = port
    _from = from

    try
      _ssl = ssl_ctx.client(host)?
    else
      _ssl_failed = true
    end

    _resize_read_buffer_if_needed()

    enclosing._finish_initialization()

  new ssl_server(auth: TCPServerAuth,
    ssl_ctx: SSLContext val,
    fd': U32,
    enclosing: TCPConnectionActor ref,
    ler: ServerLifecycleEventReceiver ref)
  =>
    """
    Create a server-side SSL connection. The SSL session is created from the
    provided SSLContext. If session creation fails, the connection reports
    failure asynchronously via _on_start_failure() and closes the fd.
    """
    _fd = fd'
    _lifecycle_event_receiver = ler
    _enclosing = enclosing

    try
      _ssl = ssl_ctx.server()?
    else
      _ssl_failed = true
    end

    _resize_read_buffer_if_needed()

    enclosing._finish_initialization()

  new none() =>
    _enclosing = None
    _lifecycle_event_receiver = None

  fun keepalive(secs: U32) =>
    """
    Sets the TCP keepalive timeout to approximately `secs` seconds. Exact
    timing is OS dependent. If `secs` is zero, TCP keepalive is disabled. TCP
    keepalive is disabled by default. This can only be set on a connected
    socket.
    """
    if _connected then
      PonyTCP.keepalive(_fd, secs)
    end

  fun local_address(): net.NetAddress =>
    """
    Return the local IP address. If this TCPConnection is closed then the
    address returned is invalid.
    """
    let ip = recover net.NetAddress end
    PonyTCP.sockname(_fd, ip)
    ip

  fun remote_address(): net.NetAddress =>
    """
    Return the remote IP address. If this TCPConnection is closed then the
    address returned is invalid.
    """
    let ip = recover net.NetAddress end
    PonyTCP.peername(_fd, ip)
    ip

  fun ref mute() =>
    """
    Temporarily suspend reading off this TCPConnection until such time as
    `unmute` is called.
    """
    _muted = true

  fun ref unmute() =>
    """
    Start reading off this TCPConnection again after having been muted.
    """
    _muted = false
    // Trigger a read in case we ignored any previous ASIO notifications
    _queue_read()

  fun ref expect(qty: USize) ? =>
    match _lifecycle_event_receiver
    | let _: EitherLifecycleEventReceiver =>
      let final_qty = match _ssl
      | let _: SSL ref =>
        // Store the application's expect value for SSL read chunking.
        // Tell the TCP read layer to read all available (0) since SSL
        // record framing doesn't align with application framing.
        _ssl_expect = qty
        USize(0)
      | None =>
        qty
      end

      if final_qty <= _read_buffer_size then
        _expect = final_qty
      else
        // saying you want a chunk larger than the max size would result
        // in a livelock of never being able to read it as we won't allow
        // you to surpass the max buffer size
        error
      end
    | None =>
      _Unreachable()
    end

  fun ref close() =>
    """
    Attempt to perform a graceful shutdown. Don't accept new writes.

    During the connecting phase (Happy Eyeballs in progress), marks the
    connection as closed so straggler events clean up instead of establishing
    a connection. Once all in-flight connections have drained,
    `_on_connection_failure()` fires.

    If the connection is established and not muted, we won't finish closing
    until we get a zero length read. If the connection is muted, perform a
    hard close and shut down immediately.
    """
    if _muted then
      hard_close()
    else
      _close()
    end

  fun ref hard_close() =>
    """
    When an error happens, do a non-graceful close.
    """
    if not _connected then
      if not _closed then
        // Connecting phase (Happy Eyeballs in progress). Mark closed so
        // straggler events clean up instead of establishing a connection.
        _closed = true
        _shutdown = true
        _shutdown_peer = true
        match _ssl
        | let ssl: SSL ref =>
          ssl.dispose()
          _ssl = None
        end
        match _lifecycle_event_receiver
        | let c: ClientLifecycleEventReceiver ref =>
          c._on_connection_failure()
        end
      end
      return
    end

    _connected = false
    _closed = true
    _shutdown = true
    _shutdown_peer = true

    // Fire _on_send_failed for any accepted-but-undelivered send before
    // clearing the pending buffer. This is deferred via _notify_send_failed
    // so it arrives in a subsequent turn, after _on_closed.
    match (_pending_token, _enclosing)
    | (let t: SendToken, let e: TCPConnectionActor ref) =>
      e._notify_send_failed(t)
    end

    _pending.clear()
    _pending_token = None

    PonyAsio.unsubscribe(_event)
    _set_unreadable()
    _set_unwriteable()

    // On windows, this will also cancel all outstanding IOCP operations.
    PonyTCP.close(_fd)
    _fd = -1

    match _ssl
    | let ssl: SSL ref =>
      ssl.dispose()
    end

    match _lifecycle_event_receiver
    | let s: EitherLifecycleEventReceiver ref =>
      match _ssl
      | let _: SSL ref =>
        if not _ssl_ready then
          // _tls_upgrade distinguishes initial SSL (constructor) from
          // mid-stream TLS upgrade (start_tls). Changing _tls_upgrade
          // semantics or removing it would break the callback routing
          // here and in _ssl_poll().
          if _tls_upgrade then
            // TLS upgrade handshake failed. The application already received
            // _on_connected/_on_started for the original plaintext connection,
            // so _on_closed must follow for cleanup.
            s._on_tls_failure()
            s._on_closed()
          else
            // Initial SSL handshake never completed. For clients, the
            // application never learned the connection existed. For servers,
            // the connection never started.
            match s
            | let c: ClientLifecycleEventReceiver ref =>
              c._on_connection_failure()
            | let srv: ServerLifecycleEventReceiver ref =>
              srv._on_start_failure()
            end
          end
        else
          s._on_closed()
        end
      | None =>
        s._on_closed()
      end
    | None =>
      _Unreachable()
    end

    match _lifecycle_event_receiver
    | let e: ServerLifecycleEventReceiver ref =>
      match _spawned_by
      | let spawner: TCPListenerActor =>
        spawner._connection_closed()
        _spawned_by = None
      | None =>
        // It is possible that we didn't yet receive the message giving us
        // our spawner. Do nothing in that case.
        None
      end
    end

  fun is_open(): Bool =>
    _connected and not _closed

  fun is_closed(): Bool =>
    _closed

  fun is_writeable(): Bool =>
    """
    Returns whether the connection can currently accept a `send()` call.
    Checks that the connection is open, the socket is writeable, and any
    SSL layer has completed its handshake.
    """
    if not (is_open() and _writeable) then
      return false
    end

    match _ssl
    | let _: SSL box => _ssl_ready
    | None => true
    end

  fun ref start_tls(ssl_ctx: SSLContext val, host: String = ""):
    (None | StartTLSError)
  =>
    """
    Initiate a TLS handshake on an established plaintext connection. Returns
    `None` when the handshake has been started, or a `StartTLSError` if the
    upgrade cannot proceed (the connection is unchanged in that case).

    Preconditions: the connection must be open, not already TLS, not muted,
    have no unprocessed data in the read buffer, and have no pending writes.
    The read buffer check prevents a man-in-the-middle from injecting pre-TLS
    data that the application would process as post-TLS (CVE-2021-23222).

    On success, `_on_tls_ready()` fires when the handshake completes. During
    the handshake, `send()` returns `SendErrorNotConnected`. If the handshake
    fails, `_on_tls_failure()` fires followed by `_on_closed()`.

    The `host` parameter is used for SNI (Server Name Indication) on client
    connections. Pass an empty string for server connections or when SNI is
    not needed.
    """
    if not is_open() then
      return StartTLSNotConnected
    end

    match _ssl
    | let _: SSL ref => return StartTLSAlreadyTLS
    end

    if _muted or (_bytes_in_read_buffer > 0) or _has_pending_writes() then
      return StartTLSNotReady
    end

    let ssl = try
      match _lifecycle_event_receiver
      | let _: ClientLifecycleEventReceiver ref =>
        ssl_ctx.client(host)?
      | let _: ServerLifecycleEventReceiver ref =>
        ssl_ctx.server()?
      | None =>
        _Unreachable()
        return StartTLSSessionFailed
      end
    else
      return StartTLSSessionFailed
    end

    _ssl_expect = _expect
    _expect = 0
    _tls_upgrade = true
    _ssl = consume ssl
    _ssl_ready = false
    _ssl_flush_sends()
    None

  fun ref send(data: ByteSeq): (SendToken | SendError) =>
    """
    Send data on this connection. Returns a `SendToken` on success, or a
    `SendError` explaining the failure. When successful, `_on_sent(token)`
    will fire in a subsequent behavior turn once the data has been fully
    handed to the OS.
    """
    if not is_open() then
      return SendErrorNotConnected
    end

    if not _writeable then
      return SendErrorNotWriteable
    end

    match _ssl
    | let _: SSL ref =>
      if not _ssl_ready then
        return SendErrorNotConnected
      end
    end

    _next_token_id = _next_token_id + 1
    let token = SendToken._create(_next_token_id)

    match _ssl
    | let ssl: SSL ref =>
      try ssl.write(data)? end
      _ssl_flush_sends()

      // Check if SSL error triggered close
      if not is_open() then
        return SendErrorNotConnected
      end
    | None =>
      _send_final(data)
    end

    // Determine when to fire _on_sent
    if not _has_pending_writes() then
      // All data sent to OS immediately; defer _on_sent
      match _enclosing
      | let e: TCPConnectionActor ref =>
        e._notify_sent(token)
      | None =>
        _Unreachable()
      end
    else
      // Partial write; _on_sent fires when pending list drains
      _pending_token = token
    end

    token

  fun ref _close() =>
    _closed = true
    _try_shutdown()

  fun ref _try_shutdown() =>
    """
    If we have closed and we have no remaining writes or pending connections,
    then shutdown.
    """
    if not _closed then
      return
    end

    if not _shutdown and (_inflight_connections == 0) then
      _shutdown = true
      if _connected then
        PonyTCP.shutdown(_fd)
      else
        _shutdown_peer = true
      end
    end

    if _shutdown and _shutdown_peer then
      if _connected then
        hard_close()
      else
        // close() during connecting phase — all inflight connections have
        // drained without establishing a connection. Dispose SSL and fire
        // the failure callback.
        match _ssl
        | let ssl: SSL ref =>
          ssl.dispose()
          _ssl = None
        end
        match _lifecycle_event_receiver
        | let c: ClientLifecycleEventReceiver ref =>
          c._on_connection_failure()
        end
      end
    end

  fun ref _send_final(data: ByteSeq) =>
    if (data.size() == 0) then
      return
    end

    if is_open() then
      ifdef windows then
        try
          PonyTCP.send(_event, data, 0)?
        else
          close()
        end
      else
        _pending.push((data, 0))
        _send_pending_writes()
      end
    end

  fun ref _send_pending_writes() =>
    """
    Send pending write data.
    This is POSIX only.
    """
    ifdef posix then
      while _writeable and _has_pending_writes() do
        try
          let node = _pending.head()?
          (let data, let offset) = node()?

          let len = PonyTCP.send(_event, data, offset)?

          if (len + offset) < data.size() then
            // not all data was sent
            node()? = (data, offset + len)
            _apply_backpressure()
          else
            _pending.shift()?
          end
        else
          // Non-graceful shutdown on error.
          hard_close()
        end
      end

      if not _has_pending_writes() then
        // Release backpressure before deferring _on_sent so the
        // application sees settled backpressure state when the
        // callback fires.
        _release_backpressure()

        match _pending_token
        | let t: SendToken =>
          _pending_token = None
          match _enclosing
          | let e: TCPConnectionActor ref =>
            e._notify_sent(t)
          | None =>
            _Unreachable()
          end
        end
      end
    else
      _Unreachable()
    end

  fun ref _write_completed(len: U32) =>
    """
    The OS has informed us that `len` bytes of pending writes have completed.
    This occurs only with IOCP on Windows.
    """
    ifdef windows then
      if len == 0 then
        // Chunk failed to write
        close()
        return
      end

      // TODO we have no way to report if a write was successful or not
      None
    else
      _Unreachable()
    end

  fun ref _deliver_received(s: EitherLifecycleEventReceiver ref,
    data: Array[U8] iso)
  =>
    """
    Route incoming data through SSL decryption (if present) or directly
    to the lifecycle event receiver.
    """
    match _ssl
    | let ssl: SSL ref =>
      ssl.receive(consume data)
      _ssl_poll(s)
    | None =>
      s._on_received(consume data)
    end

  fun ref _read() =>
    ifdef posix then
      match _lifecycle_event_receiver
      | let s: EitherLifecycleEventReceiver ref =>
        try
          var total_bytes_read: USize = 0

          while _readable and not _shutdown_peer do
            // exit if muted
            if _muted then
              return
            end

            // Handle any data already in the read buffer
            while not _muted and _there_is_buffered_read_data() do
              let bytes_to_consume = if _expect == 0 then
                // if we aren't getting in `_expect` chunks,
                // we should grab all the bytes that are currently available
                _bytes_in_read_buffer
              else
                _expect
              end

              let x = _read_buffer = recover Array[U8] end
              (let data', _read_buffer) = (consume x).chop(bytes_to_consume)
              _bytes_in_read_buffer = _bytes_in_read_buffer - bytes_to_consume

              _deliver_received(s, consume data')
            end

            if total_bytes_read >= _read_buffer_size then
              _queue_read()
            end

            _resize_read_buffer_if_needed()

            let bytes_read = PonyTCP.receive(_event,
              _read_buffer.cpointer(_bytes_in_read_buffer),
              _read_buffer.size() - _bytes_in_read_buffer)?

            if bytes_read == 0 then
              // would block. try again later
              _set_unreadable()
              PonyAsio.resubscribe_read(_event)
              return
            end

            _bytes_in_read_buffer = _bytes_in_read_buffer + bytes_read
            total_bytes_read = total_bytes_read + bytes_read
          end
        else
          // The socket has been closed from the other side.
          _shutdown_peer = true
          hard_close()
        end
      | None =>
        _Unreachable()
      end
    else
      _Unreachable()
    end

  fun ref _iocp_read() =>
    ifdef windows then
      try
        PonyTCP.receive(_event,
          _read_buffer.cpointer(_bytes_in_read_buffer),
          _read_buffer.size() - _bytes_in_read_buffer)?
      else
        close()
      end
    else
      _Unreachable()
    end

  fun ref _read_completed(len: U32) =>
    """
    The OS has informed us that `len` bytes of data has been read and is now
    available.
    """
    ifdef windows then
      match _lifecycle_event_receiver
      | let s: EitherLifecycleEventReceiver ref =>
        if len == 0 then
          // The socket has been closed from the other side, or a hard close has
          // cancelled the queued read.
          _set_unreadable()
          _shutdown_peer = true
          close()
          return
        end

        // Handle the data
        _bytes_in_read_buffer = _bytes_in_read_buffer + len.usize()

        while not _muted and _there_is_buffered_read_data()
        do
          // get data to be distributed and update `_bytes_in_read_buffer`
          let chop_at = if _expect == 0 then
            _bytes_in_read_buffer
          else
            _expect
          end
          (let data, _read_buffer) = (consume _read_buffer).chop(chop_at)
          _bytes_in_read_buffer = _bytes_in_read_buffer - chop_at

          _deliver_received(s, consume data)

          _resize_read_buffer_if_needed()
        end

        _queue_read()
      | None =>
        _Unreachable()
      end
    else
      _Unreachable()
    end

  fun _there_is_buffered_read_data(): Bool =>
    (_bytes_in_read_buffer >= _expect) and (_bytes_in_read_buffer > 0)

  fun ref _resize_read_buffer_if_needed() =>
    """
    Resize the read buffer if it's empty or smaller than expected data size
    """
    if _read_buffer.size() <= _expect then
      _read_buffer.undefined(_read_buffer_size)
    end

  fun ref _queue_read() =>
    ifdef posix then
      // Trigger a read in case we ignored any previous ASIO notifications
      match _enclosing
      | let e: TCPConnectionActor ref =>
        e._read_again()
        return
      | None =>
        _Unreachable()
      end
    else
      _iocp_read()
    end

  fun ref _apply_backpressure() =>
    match _lifecycle_event_receiver
    | let s: EitherLifecycleEventReceiver =>
      if not _throttled then
        _throttled = true
        // throttled means we are also unwriteable
        // being unthrottled doesn't however mean we are writable
        _set_unwriteable()
        ifdef not windows then
          PonyAsio.resubscribe_write(_event)
        end
        s._on_throttled()
      end
    | None =>
      _Unreachable()
    end

  fun ref _release_backpressure() =>
    match _lifecycle_event_receiver
    | let s: EitherLifecycleEventReceiver =>
      if _throttled then
        _throttled = false
        s._on_unthrottled()
      end
    | None =>
      _Unreachable()
    end

  fun ref _fire_on_sent(token: SendToken) =>
    """
    Dispatch _on_sent to the lifecycle event receiver. Called from
    _notify_sent behavior on TCPConnectionActor.
    """
    match _lifecycle_event_receiver
    | let s: EitherLifecycleEventReceiver ref =>
      s._on_sent(token)
    | None =>
      _Unreachable()
    end

  fun ref _fire_on_send_failed(token: SendToken) =>
    """
    Dispatch _on_send_failed to the lifecycle event receiver. Called from
    _notify_send_failed behavior on TCPConnectionActor.
    """
    match _lifecycle_event_receiver
    | let s: EitherLifecycleEventReceiver ref =>
      s._on_send_failed(token)
    | None =>
      _Unreachable()
    end

  fun ref _ssl_flush_sends() =>
    """
    Flush any pending encrypted data from the SSL session to the wire.
    Called after SSL operations that may produce output (handshake, write).
    """
    match _ssl
    | let ssl: SSL ref =>
      try
        while ssl.can_send() do
          _send_final(ssl.send()?)
        end
      end
    end

  fun ref _ssl_poll(s: EitherLifecycleEventReceiver ref) =>
    """
    Check SSL state after receiving data. Handles handshake completion,
    error detection, decrypted data delivery, and protocol data flushing.
    """
    match _ssl
    | let ssl: SSL ref =>
      match ssl.state()
      | SSLReady =>
        if not _ssl_ready then
          _ssl_ready = true
          // _tls_upgrade distinguishes initial SSL (constructor) from
          // mid-stream TLS upgrade (start_tls). Changing _tls_upgrade
          // semantics or removing it would break the callback routing
          // here and in hard_close().
          if _tls_upgrade then
            s._on_tls_ready()
          else
            match s
            | let c: ClientLifecycleEventReceiver ref =>
              c._on_connected()
            | let srv: ServerLifecycleEventReceiver ref =>
              srv._on_started()
            end
          end
        end
      | SSLAuthFail =>
        hard_close()
        return
      | SSLError =>
        hard_close()
        return
      end

      // Read all available decrypted data
      while true do
        match ssl.read(_ssl_expect)
        | let d: Array[U8] iso => s._on_received(consume d)
        | None => break
        end
      end

      // Flush any SSL protocol data (handshake responses, etc.)
      _ssl_flush_sends()
    end

  fun _has_pending_writes(): Bool =>
    _pending.size() != 0

  fun ref _event_notify(event: AsioEventID, flags: U32, arg: U32) =>
    if event is _event then
      if AsioEvent.writeable(flags) then
        _set_writeable()
        ifdef windows then
          _write_completed(arg)
        else
          _send_pending_writes()
        end
      end

      if AsioEvent.readable(flags) then
        _set_readable()
        ifdef windows then
          _read_completed(arg)
        else
          _read()
        end
      end

      if AsioEvent.disposable(flags) then
        PonyAsio.destroy(event)
        _event = AsioEvent.none()
      end

      _try_shutdown()
    else
      if AsioEvent.writeable(flags) then
        let fd = PonyAsio.event_fd(event)
        _inflight_connections = _inflight_connections - 1

        if not _connected and not _closed then
          // We don't have a connection yet so we are a client
          match _lifecycle_event_receiver
          | let c: ClientLifecycleEventReceiver ref =>
            if _is_socket_connected(fd) then
              _event = event
              _fd = fd
              _connected = true
              _set_writeable()
              _set_readable()

              match _ssl
              | let _: SSL ref =>
                // Flush ClientHello to initiate SSL handshake
                _ssl_flush_sends()
                // _on_connected() deferred until _ssl_ready
              | None =>
                c._on_connected()
              end

              ifdef windows then
                _queue_read()
              else
                _read()
                if _has_pending_writes() then
                  _send_pending_writes()
                end
              end
            else
              PonyAsio.unsubscribe(event)
              PonyTCP.close(fd)
              _connecting_callback()
            end
          | None =>
            _Unreachable()
          end
        else
          // There is a possibility that a non-Windows system has
          // already unsubscribed this event already.  (Windows might
          // be vulnerable to this race, too, I'm not sure.) It's a
          // bug to do a second time.  Look at the disposable status
          // of the event (not the flags that this behavior's args!)
          // to see if it's ok to unsubscribe.
          if not PonyAsio.get_disposable(event) then
            PonyAsio.unsubscribe(event)
          end
          PonyTCP.close(fd)
          _try_shutdown()
        end
      else
        if AsioEvent.disposable(flags) then
          PonyAsio.destroy(event)
        end
      end
    end

  fun ref _connecting_callback() =>
    match _lifecycle_event_receiver
    | let c: ClientLifecycleEventReceiver ref =>
      if _inflight_connections > 0 then
        c._on_connecting(_inflight_connections)
      else
        hard_close()
      end
    | let s: ServerLifecycleEventReceiver ref =>
      _Unreachable()
    | None =>
      _Unreachable()
    end

  fun _is_socket_connected(fd: U32): Bool =>
    ifdef windows then
      (let errno: U32, let value: U32) = _OSSocket.get_so_connect_time(fd)
      (errno == 0) and (value != 0xffffffff)
    else
      (let errno: U32, let value: U32) = _OSSocket.get_so_error(fd)
      (errno == 0) and (value == 0)
    end

  fun ref _register_spawner(listener: TCPListenerActor) =>
    if _spawned_by is None then
      if not _closed then
        // We were connected by the time the spawner was registered,
        // so, let's let it know we were connected
        _spawned_by = listener
      else
        // We were closed by the time the spawner was registered,
        // so, let's let it know we were closed, And leave our "spawned by" as
        // None.
        listener._connection_closed()
      end
    else
      _Unreachable()
    end

  fun ref _finish_initialization() =>
    match _lifecycle_event_receiver
    | let s: ServerLifecycleEventReceiver ref =>
      _complete_server_initialization(s)
    | let c: ClientLifecycleEventReceiver ref =>
      _complete_client_initialization(c)
    | None =>
      _Unreachable()
    end

  fun ref _complete_client_initialization(
    s: ClientLifecycleEventReceiver ref)
  =>
    if _ssl_failed then
      s._on_connection_failure()
      return
    end

    match _enclosing
    | let e: TCPConnectionActor ref =>
      let asio_flags = ifdef windows then
        AsioEvent.read_write()
      else
        AsioEvent.read_write_oneshot()
      end

      _inflight_connections = PonyTCP.connect(e, _host, _port, _from, asio_flags)
      _connecting_callback()
    | None =>
      _Unreachable()
    end

  fun ref _complete_server_initialization(
    s: ServerLifecycleEventReceiver ref)
  =>
    if _ssl_failed then
      PonyTCP.close(_fd)
      _fd = -1
      _closed = true
      s._on_start_failure()
      return
    end

    match _enclosing
    | let e: TCPConnectionActor ref =>
      _event = PonyAsio.create_event(e, _fd)
      _connected = true
      _set_readable()
      _set_writeable()

      match _ssl
      | let _: SSL ref =>
        // Flush any initial SSL data (usually no-op for servers)
        _ssl_flush_sends()
        // _on_started() deferred until _ssl_ready
      | None =>
        s._on_started()
      end

      // Queue up reads as we are now connected
      // But might have been in a race with ASIO
      _queue_read()
    | None =>
      _Unreachable()
    end

  fun ref _set_readable() =>
    _readable = true
    PonyAsio.set_readable(_event)

  fun ref _set_unreadable() =>
    _readable = false
    PonyAsio.set_unreadable(_event)

  fun ref _set_writeable() =>
    _writeable = true
    PonyAsio.set_writeable(_event)

  fun ref _set_unwriteable() =>
    _writeable = false
    PonyAsio.set_unwriteable(_event)
