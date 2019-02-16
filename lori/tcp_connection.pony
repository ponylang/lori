use "collections"

class TCPConnection
  var fd: U32 = -1
  var _event: AsioEventID = AsioEvent.none()
  var _state: U32 = 0
  let _enclosing: (TCPConnectionActor ref | None)
  let _pending: List[(ByteSeq, USize)] = _pending.create()

  new client(host: String,
    port: String,
    from: String,
    enclosing: TCPConnectionActor ref)
  =>
    // TODO: handle happy eyeballs here - connect count
    _enclosing = enclosing
    PonyTCP.connect(enclosing, host, port, from)

  new server(fd': U32, enclosing: TCPConnectionActor ref) =>
    fd = fd'
    // TODO: sort out client and server side setup. it's a mess
    _enclosing = enclosing
    _event = PonyASIO.create_event(enclosing, fd)
    open()
    // should set readable state
    enclosing.on_connected()

  new none() =>
    """
    For initializing an empty variable
    """
    _enclosing = None

  fun ref open() =>
    // TODO: should this be private? I think so.
    // I don't think the actor that is using the connection should
    // ever need this.
    // client-  open() gets called from our event_notify
    // server- calls this
    //
    // seems like no need to call from external
    _state = BitSet.set(_state, 0)
    writeable()

  fun is_open(): Bool =>
    BitSet.is_set(_state, 0)

  fun ref close() =>
    if is_open() then
      _state = BitSet.unset(_state, 0)
      unwriteable()
      PonyTCP.shutdown(fd)
      PonyASIO.unsubscribe(_event)
      fd = -1
    end

  fun is_closed(): Bool =>
    not is_open()

  fun ref send(data: ByteSeq) =>
    if is_open() then
      if is_writeable() then
        if has_pending_writes() then
          try
            let len = PonyTCP.send(_event, data)?
            if (len < data.size()) then
              // unable to write all data
              _pending.push((data, len))
              _apply_backpressure()
            end
          else
            // TODO: is there any way to get here if connnection is open?
            return
          end
        else
          _pending.push((data, 0))
          _send_pending_writes()
        end
      else
        _pending.push((data, 0))
      end
    else
      // TODO: handle trying to send on a closed connection
      // maybe an error?
      return
    end

  fun ref _send_pending_writes() =>
    while is_writeable() and has_pending_writes() do
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
        // error sending. appears our connection has been shutdown.
        // TODO: handle close here
        None
      end
    end

    if has_pending_writes() then
      // all pending data was sent
      _release_backpressure()
    end

  fun is_writeable(): Bool =>
    BitSet.is_set(_state, 1)

  fun ref writeable() =>
    _state = BitSet.set(_state, 1)

  fun ref unwriteable() =>
    _state = BitSet.unset(_state, 1)

  fun ref read() =>
    match _enclosing
    | let s: TCPConnectionActor ref =>
      try
        if is_open() then
          let buffer = recover Array[U8].>undefined(64) end
          let bytes_read = PonyTCP.receive(_event,
          buffer.cpointer(),
          buffer.size())?
          if (bytes_read == 0) then
            PonyASIO.set_unreadable(_event)
            // would block. try again later
            // TCPConnection handles with:
            //@pony_asio_event_set_readable[None](self().event, false)
            // _readable = false
            // @pony_asio_event_resubscribe_read(_event)
            return
          end

          buffer.truncate(bytes_read)
          s.on_received(consume buffer)
          s._read_again()
        end
      else
        // Socket shutdown from other side
        close()
      end
    | None =>
      // TODO: SHOULD WE BLOW UP WITH SOME SORT OF UNREACHABLE HERE?
      None
    end

  fun ref _apply_backpressure() =>
    match _enclosing
    | let s: TCPConnectionActor ref =>
      if not is_throttled() then
        throttled()
        s.on_throttled()
      end
    | None =>
      // TODO: Blow up here!
      None
    end

  fun ref _release_backpressure() =>
    match _enclosing
    | let s: TCPConnectionActor ref =>
      if is_throttled() then
        unthrottled()
        s.on_unthrottled()
      end
    | None =>
      // TODO: blow up here
      None
    end

  fun is_throttled(): Bool =>
    BitSet.is_set(_state, 2)

  fun ref throttled() =>
    _state = BitSet.set(_state, 2)
    // throttled means we are also unwriteable
    // being unthrottled doesn't however mean we are writable
    unwriteable()
    PonyASIO.set_unwriteable(_event)

  fun ref unthrottled() =>
    _state = BitSet.unset(_state, 2)

  fun has_pending_writes(): Bool =>
    _pending.size() != 0

  fun ref event_notify(event: AsioEventID,
    flags: U32,
    arg: U32)
  =>
    match _enclosing
    | let s: TCPConnectionActor ref =>
      if event isnt _event then
        if AsioEvent.writeable(flags) then
          // TODO: this assumes the connection succeed. That might not be true.
          // more logic needs to go here
          fd = PonyASIO.event_fd(event)
          _event = event
          open()
          s.on_connected()
          read()
        end
      end

      if event is _event then
        if AsioEvent.readable(flags) then
          // should set that we are readable
          read()
        end

        if AsioEvent.writeable(flags) then
          writeable()
          _send_pending_writes()
        end

        if AsioEvent.disposable(flags) then
          PonyASIO.destroy(event)
          _event = AsioEvent.none()
        end
      end
    | None =>
      // TODO: blow up here
      None
    end
