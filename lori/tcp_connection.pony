use "collections"

class TCPConnection
  var fd: U32 = -1
  var _event: AsioEventID = AsioEvent.none()
  var _state: U32 = 0
  let _pending: List[(ByteSeq, USize)] = _pending.create()

  new client() =>
    None

  new server(fd': U32, sender: TCPConnectionActor ref) =>
    fd = fd'
    // TODO: sort out client and server side setup. it's a mess
    _event = PonyASIO.create_event(sender, fd)
    open()
    // should set readable state
    sender.on_connected()

  new none() =>
    """
    For initializing an empty variable
    """
    None

  fun ref open() =>
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

  fun ref send(sender: TCPConnectionActor ref, data: ByteSeq) =>
    if is_open() then
      if is_writeable() then
        if has_pending_writes() then
          try
            let len = PonyTCP.send(_event, data)?
            if (len < data.size()) then
              // unable to write all data
              _pending.push((data, len))
              _apply_backpressure(sender)
            end
          else
            // TODO: is there any way to get here if connnection is open?
            return
          end
        else
          _pending.push((data, 0))
          _send_pending_writes(sender)
        end
      else
        _pending.push((data, 0))
      end
    end

  fun ref _send_pending_writes(sender: TCPConnectionActor ref) =>
    while is_writeable() and has_pending_writes() do
      try
        let node = _pending.head()?
        (let data, let offset) = node()?

        let len = PonyTCP.send(_event, data, offset)?

        if (len + offset) < data.size() then
          // not all data was sent
          node()? = (data, offset + len)
          _apply_backpressure(sender)
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
      _release_backpressure(sender)
    end

  fun is_writeable(): Bool =>
    BitSet.is_set(_state, 1)

  fun ref writeable() =>
    _state = BitSet.set(_state, 1)

  fun ref unwriteable() =>
    _state = BitSet.unset(_state, 1)

  fun ref read(sender: TCPConnectionActor ref) =>
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
        sender.on_received(consume buffer)
        sender._read_again()
      end
    else
      // Socket shutdown from other side
      close()
    end

  fun ref _apply_backpressure(sender: TCPConnectionActor ref) =>
    if not is_throttled() then
      throttled()
      sender.on_throttled()
    end

  fun ref _release_backpressure(sender: TCPConnectionActor ref) =>
    if is_throttled() then
      unthrottled()
      sender.on_unthrottled()
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

  fun ref event_notify(sender: TCPConnectionActor ref,
    event: AsioEventID,
    flags: U32,
    arg: U32)
  =>
    if event isnt _event then
      if AsioEvent.writeable(flags) then
        // TODO: this assumes the connection succeed. That might not be true.
        // more logic needs to go here
        fd = PonyASIO.event_fd(event)
        _event = event
        open()
        sender.on_connected()
        read(sender)
      end
    end

    if event is _event then
      if AsioEvent.readable(flags) then
        // should set that we are readable
        read(sender)
      end

      if AsioEvent.writeable(flags) then
        writeable()
        _send_pending_writes(sender)
      end

      if AsioEvent.disposable(flags) then
        PonyASIO.destroy(event)
        _event = AsioEvent.none()
      end
    end
