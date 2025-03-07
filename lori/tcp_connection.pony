use "collections"
use net = "net"

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
  var _connection_token: (_OpenConnectionToken | None) = None
  let _lifecycle_event_receiver: (ClientLifecycleEventReceiver ref | ServerLifecycleEventReceiver ref | None)
  let _enclosing: (TCPConnectionActor ref| None)
  let _pending: List[(ByteSeq, USize)] = _pending.create()
  var _read_buffer: Array[U8] iso = recover Array[U8] end
  var _bytes_in_read_buffer: USize = 0
  var _read_buffer_size: USize = 16384
  var _expect: USize = 0

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
    ifdef posix then
      // Trigger a read in case we ignored any previous ASIO notifications
      match _enclosing
      | let e: TCPConnectionActor ref =>
        e._read_again()
        return
      | None =>
        _Unreachable()
      end
    end

  fun ref expect(qty: USize) ? =>
    match _lifecycle_event_receiver
    | let s: EitherLifecycleEventReceiver =>
      let final_qty = s._on_expect_set(qty)
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
    Attempt to perform a graceful shutdown. Don't accept new writes. If the
    connection isn't muted then we won't finish closing until we get a zero
    length read. If the connection is muted, perform a hard close and shut
    down immediately.
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
      return
    end

    _connected = false
    _closed = true
    _shutdown = true
    _shutdown_peer = true

    _pending.clear()

    PonyAsio.unsubscribe(_event)
    _readable = false
    _writeable = false
    PonyAsio.set_unreadable(_event)
    PonyAsio.set_unwriteable(_event)

    // On windows, this will also cancel all outstanding IOCP operations.
    PonyTCP.close(_fd)
    _fd = -1

    match _lifecycle_event_receiver
    | let s: EitherLifecycleEventReceiver ref =>
      s._on_closed()
    | None =>
      _Unreachable()
    end

    match _lifecycle_event_receiver
    | let e: ServerLifecycleEventReceiver ref =>
      match (_spawned_by, _connection_token)
      | (let spawner: TCPListenerActor, let token: _OpenConnectionToken) =>
        spawner._connection_closed(token)
      | (None, _) =>
        // It is possible that we didn't yet receive the message giving us
        // our spawner. Do nothing in that case.
        None
      | (let _: TCPListenerActor, None) =>
        _Unreachable()
      end
    end

  fun is_open(): Bool =>
    _connected and not _closed

  fun is_closed(): Bool =>
    _closed

  fun ref send(data: ByteSeq) =>
    // TODO: should we be checking if we are open here?
    match _lifecycle_event_receiver
    | let s: EitherLifecycleEventReceiver ref =>
      match s._on_send(data)
      | let seq: ByteSeq =>
        _send_final(seq)
      end
    | None =>
      _Unreachable()
    end

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

    if _connected and _shutdown and _shutdown_peer then
      hard_close()
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
        // all pending data was sent
        _release_backpressure()
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

              s._on_received(consume data')
            end

            if total_bytes_read >= _read_buffer_size then
              match _enclosing
              | let e: TCPConnectionActor ref =>
                e._read_again()
                return
              else
                _Unreachable()
              end
            end

            _resize_read_buffer_if_needed()

            let bytes_read = PonyTCP.receive(_event,
              _read_buffer.cpointer(_bytes_in_read_buffer),
              _read_buffer.size() - _bytes_in_read_buffer)?

            if bytes_read == 0 then
              // would block. try again later
              _readable = false
              PonyAsio.set_unreadable(_event)
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
          _readable = false
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

          s._on_received(consume data)

          _resize_read_buffer_if_needed()
        end

        _iocp_read()
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

  fun ref _apply_backpressure() =>
    match _lifecycle_event_receiver
    | let s: EitherLifecycleEventReceiver =>
      if not _throttled then
        _throttled = true
        // throttled means we are also unwriteable
        // being unthrottled doesn't however mean we are writable
        _writeable = false
        PonyAsio.set_unwriteable(_event)
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

  fun _has_pending_writes(): Bool =>
    _pending.size() != 0

  fun ref _event_notify(event: AsioEventID, flags: U32, arg: U32) =>
    if event is _event then
      if AsioEvent.writeable(flags) then
        _writeable = true
        ifdef windows then
          _write_completed(arg)
        else
          _send_pending_writes()
        end
      end

      if AsioEvent.readable(flags) then
        _readable = true
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
              _writeable = true
              _readable = true
              c._on_connected()
              ifdef windows then
                _iocp_read()
              else
                _read()
                if _has_pending_writes() then
                  _send_pending_writes()
                  _release_backpressure()
                end
              end
            else
              PonyAsio.unsubscribe(event)
              PonyTCP.close(fd)
              hard_close()
              _connecting_callback()
            end
          | None =>
            _Unreachable()
          end
        else
          if not PonyAsio.get_disposable(event) then
            PonyAsio.unsubscribe(event)
          end
          PonyTCP.close(fd)
          ifdef windows then
            _try_shutdown()
          end
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
        c._on_connection_failure()
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

  fun ref _register_spawner(listener: TCPListenerActor, token: _OpenConnectionToken) =>
    _spawned_by = listener
    _connection_token = token
    match _spawned_by
    | let spawner: TCPListenerActor =>
      if _connected then
        // We were connected by the time the spawner was registered,
        // so, let's let it know we were connected
        spawner._connection_opened(token)
      end
      if _closed then
        // We were closed by the time the spawner was registered,
        // so, let's let it know we were closed
        spawner._connection_closed(token)
      end
    | None =>
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
    match _enclosing
    | let e: TCPConnectionActor ref =>
      _event = PonyAsio.create_event(e, _fd)
      _connected = true
      ifdef not windows then
        PonyAsio.set_writeable(_event)
      end
      _writeable = true

      s._on_started()

      _readable = true
      // Queue up reads as we are now connected
      // But might have been in a race with ASIO
      ifdef windows then
        _iocp_read()
      else
        e._read_again()
      end
    | None =>
      _Unreachable()
    end
