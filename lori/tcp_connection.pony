use "collections"

class TCPConnection
  var _connected: Bool = false
  var _closed: Bool = false
  var _shutdown: Bool = false
  var _shutdown_peer: Bool = false
  var _throttled: Bool = false
  var _readable: Bool = false
  var _writeable: Bool = false

  var _fd: U32 = -1
  var _event: AsioEventID = AsioEvent.none()
  let _enclosing: (TCPClientActor ref | TCPServerActor ref | None)
  let _pending: List[(ByteSeq, USize)] = _pending.create()
  var _read_buffer: Array[U8] iso = recover Array[U8] end
  var _bytes_in_read_buffer: USize = 0
  var _read_buffer_size: USize = 16384
  var _expect: USize = 0

  new client(auth: TCPConnectAuth,
    host: String,
    port: String,
    from: String,
    enclosing: TCPClientActor ref)
  =>
    // TODO: handle happy eyeballs here - connect count
    _enclosing = enclosing

    let asio_flags = ifdef windows then
      AsioEvent.read_write()
    else
      AsioEvent.read_write_oneshot()
    end

    _resize_read_buffer_if_needed()
    PonyTCP.connect(enclosing, host, port, from, asio_flags)

  new server(auth: TCPServerAuth,
    fd': U32,
    enclosing: TCPServerActor ref)
  =>
    _fd = fd'
    _enclosing = enclosing

    _resize_read_buffer_if_needed()
    _event = PonyAsio.create_event(enclosing, _fd)
    // TODO should we be opening here? Perhaps that waits for the event

    _connected = true
    ifdef not windows then
      PonyAsio.set_writeable(_event)
    end
    _writeable = true

    match _enclosing
    | let s: TCPServerActor ref =>
      s._on_accepted()
    else
      // TODO blow up here
      None
    end

    _readable = true
    // Queue up reads as we are now connected
    // But might have been in a race with ASIO
    _iocp_read()
    enclosing._read_again()

  new none() =>
    """
    For initializing an empty variable
    """
    _enclosing = None

  fun ref expect(qty: USize) ? =>
    if qty <= _read_buffer_size then
      _expect = qty
    else
      // saying you want a chunk larger than the max size would result
      // in a livelock of never being able to read it as we won't allow
      // you to surpass the max buffer size
      error
    end

  fun ref close() =>
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

    if not _shutdown then
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

    PonyAsio.unsubscribe(_event)
    _readable = false
    _writeable = false
    PonyAsio.set_unreadable(_event)
    PonyAsio.set_unwriteable(_event)

    // On windows, this will also cancel all outstanding IOCP operations.
    PonyTCP.close(_fd)
    _fd = -1

    match _enclosing
    | let s: TCPConnectionActor ref =>
      s._on_closed()
    end

  fun is_open(): Bool =>
    _connected and not _closed

  fun is_closed(): Bool =>
    _closed

  fun ref send(data: ByteSeq) =>
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
      while _writeable and has_pending_writes() do
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

      if not has_pending_writes() then
        // all pending data was sent
        _release_backpressure()
      end
    else
      // TODO unreachable
      None
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
      // TODO unreachable
      None
    end

  // TODO should this be private? Probably.
  // There's no equiv to this on Windows with IOCP so we probably
  // want to hide all of this.
  fun ref read() =>
    ifdef posix then
      match _enclosing
      | let s: TCPConnectionActor ref =>
        try
          var total_bytes_read: USize = 0

          while _readable and not _shutdown_peer do
            // Handle any data already in the read buffer
            while _there_is_buffered_read_data() do
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
              s._read_again()
              return
            end

            _resize_read_buffer_if_needed()

            let bytes_read = PonyTCP.receive(_event,
              _read_buffer.cpointer(_bytes_in_read_buffer),
              _read_buffer.size() - _bytes_in_read_buffer)?

            if bytes_read == 0 then
              // would block. try again later
              _mark_unreadable()
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
        // TODO: SHOULD WE BLOW UP WITH SOME SORT OF UNREACHABLE HERE?
        None
      end
    else
      // TODO unreachable
      None
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
      // TODO unreachable
      None
    end

  fun ref _read_completed(len: U32) =>
    """
    The OS has informed us that `len` bytes of data has been read and is now
    available.
    """
    ifdef windows then
      match _enclosing
      | let s: TCPConnectionActor ref =>
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

        while (_bytes_in_read_buffer >= _expect)
          and (_bytes_in_read_buffer > 0)
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
      end
    else
      // TODO unreachable
      None
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
    match _enclosing
    | let s: TCPConnectionActor ref =>
      if not _throttled then
        throttled()
        s._on_throttled()
      end
    | None =>
      // TODO: Blow up here!
      None
    end

  fun ref _release_backpressure() =>
    match _enclosing
    | let s: TCPConnectionActor ref =>
      if _throttled then
        _throttled = false
        s._on_unthrottled()
      end
    | None =>
      // TODO: blow up here
      None
    end

  fun ref throttled() =>
    _throttled = true
    // throttled means we are also unwriteable
    // being unthrottled doesn't however mean we are writable
    _writeable = false
    PonyAsio.set_unwriteable(_event)
    ifdef not windows then
      PonyAsio.resubscribe_write(_event)
    end

  fun has_pending_writes(): Bool =>
    _pending.size() != 0

  fun ref event_notify(event: AsioEventID, flags: U32, arg: U32) =>
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
          read()
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
        if not _connected and not _closed then
          // We don't have a connection yet so we are a client
          match _enclosing
          | let c: TCPClientActor ref =>
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
                read()
              end
            else
              PonyAsio.unsubscribe(event)
              PonyTCP.close(fd)
              close()
              c._on_connection_failure()
            end
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

  fun ref _mark_unreadable() =>
    _readable = false
    PonyAsio.set_unreadable(_event)
    // TODO: should be able to switch from one-shot to edge-triggered without
    // changing this. need a switch based on flags that we do not have at
    // the moment
    ifdef not windows then
      PonyAsio.resubscribe_read(_event)
    end

  fun _is_socket_connected(fd: U32): Bool =>
    ifdef windows then
      (let errno: U32, let value: U32) = _OSSocket.get_so_connect_time(fd)
      (errno == 0) and (value != 0xffffffff)
    else
      (let errno: U32, let value: U32) = _OSSocket.get_so_error(fd)
      (errno == 0) and (value == 0)
    end
