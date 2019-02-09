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

  be dispose() =>
    """
    Close connection
    """
    close()

  be open() =>
    // TODO: this is kind of misnamed. coming from accept in listener.
    // would like to make this a `fun` be then, how does a listener trigger it?
    let event = PonyASIO.create_event(this, self().fd)
    self().event = event
    self().state = Open
    // should set writable state
    // should set readable state
    PonyASIO.set_writeable(self().event)
    on_connected()

  fun ref close() =>
    if self().state is Open then
      self().state = Closed
      PonyTCP.shutdown(self().fd)
      PonyASIO.unsubscribe(self().event)
      self().fd = -1
    end

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

  fun ref send(data: ByteSeq) =>
    if self().state is Open then
      try
        PonyTCP.send(self().event, data, data.size())?
      else
        // TODO: is there any way to get here if the connection is open?
        return
      end
    end

  be _event_notify(event: AsioEventID, flags: U32, arg: U32) =>
    if event isnt self().event then
      if AsioEvent.writeable(flags) then
        // more logic needs to go here
        let fd = PonyASIO.event_fd(event)
        self().fd = fd
        self().event = event
        self().state = Open
        on_connected()
      end
    end

    if event is self().event then
      if AsioEvent.readable(flags) then
        // should set that we are readable
        _read()
      end

      if AsioEvent.disposable(flags) then
        PonyASIO.destroy(event)
        self().event = AsioEvent.none()
      end
    end

  fun ref _read() =>
    try
      if self().state is Open then
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
      close()
    end

  be _read_again() =>
    """
    Resume reading
    """
    _read()

class TCPConnection
  var fd: U32
  var event: AsioEventID = AsioEvent.none()
  var state: TCPConnectionState = Closed

  new client() =>
    fd = -1

  new server(fd': U32) =>
    fd = fd'
