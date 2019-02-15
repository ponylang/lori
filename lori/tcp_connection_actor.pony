interface tag TCPConnectionActor
  fun ref self(): TCPConnection


  fun ref on_closed()
    """
    Called when the connection is closed
    """

  fun ref on_connected()
    """
    Called when a connection is opened
    """

  fun ref on_received(data: Array[U8] iso)
    """
    Called each time data is received on this connection
    """

  fun ref on_throttled() =>
    """
    Called when we start experiencing backpressure
    """

    None

  fun ref on_unthrottled() =>
    """
    Called when backpressure is released
    """

    None

  be dispose() =>
    """
    Close connection
    """
    self().close()

  be open() =>
    // TODO: this is kind of misnamed. coming from accept in listener.
    // would like to make this a `fun` be then, how does a listener trigger it?
    let event = PonyASIO.create_event(this, self().fd)
    self().event = event
    self().open()
    // should set readable state
    PonyASIO.set_writeable(self().event)
    on_connected()

  fun ref connect(host: String, port: String, from: String) =>
    """
    Called to open a new outgoing connection
    """
    let connect_count = PonyTCP.connect(this, host, port, from)
/*    if connect_count > 0 then
      // TODO: call out for connecting?
      return
    else
      // TODO: handle failure
      return
    end
*/

  be _event_notify(event: AsioEventID, flags: U32, arg: U32) =>
    if event isnt self().event then
      if AsioEvent.writeable(flags) then
        // TODO: this assumes the connection succeed. That might not be true.
        // more logic needs to go here
        let fd = PonyASIO.event_fd(event)
        self().fd = fd
        self().event = event
        self().open()
        on_connected()
        _read()
      end
    end

    if event is self().event then
      if AsioEvent.readable(flags) then
        // should set that we are readable
        _read()
      end

      if AsioEvent.writeable(flags) then
        self().writeable()
        // TODO: need this
        //self()._send_pending_writes()
      end

      if AsioEvent.disposable(flags) then
        PonyASIO.destroy(event)
        self().event = AsioEvent.none()
      end
    end

  fun ref _read() =>
    try
      if self().is_open() then
        let buffer = recover Array[U8].>undefined(64) end
        let bytes_read = PonyTCP.receive(self().event, buffer.cpointer(), buffer.size())?
        if (bytes_read == 0) then
          PonyASIO.set_unreadable(self().event)
          // would block. try again later
    // TCPConnection handles with:
          //@pony_asio_event_set_readable[None](self().event, false)
          // _readable = false
          // @pony_asio_event_resubscribe_read(_event)
    return
        end

        buffer.truncate(bytes_read)
        on_received(consume buffer)
        _read_again()
      end
    else
      // Socket shutdown from other side
      self().close()
    end

  be _read_again() =>
    """
    Resume reading
    """
    _read()
