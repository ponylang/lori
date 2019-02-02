interface tag TCPConnectionActor
  fun ref self(): TCPConnection
  
  fun ref on_connected()
  fun ref on_received(data: Array[U8] iso)

  be open() =>
    // would like to make this a `fun` be then, how does a listener trigger it?
    let event = PonyASIO.create_event(this, self().fd)
    self().event = event
    // should set connected state
    // should set writable state
    // should set readable state
    PonyASIO.set_writeable(self().event)
    on_connected()   

  fun ref send(data: ByteSeq) =>
    // check connection is open
    PonyTCP.send(self().event, data, data.size())
 
  be _event_notify(event: AsioEventID, flags: U32, arg: U32) =>
    if event isnt self().event then
      // this will happen once I add support for outgoing connections
      // in the meantime, do nothing here as I only have support for
      // incoming connections
      return
    end

    if event is self().event then
      if AsioEvent.readable(flags) then
        // should set that we are readable
        _read()
      end
    end

  fun ref _read() =>
    try
      let buffer = recover Array[U8].>undefined(64) end
      let bytes_read = PonyTCP.receive(self().event, buffer.cpointer(), buffer.size())?
      if (bytes_read == 0) then
        // would block. try again later
	// TCPConnection handles with:
        // @pony_asio_event_set_readable(_event, false)
        // _readable = false
        // @pony_asio_event_resubscribe_read(_event)
	return
      end

      buffer.truncate(bytes_read)
      on_received(consume buffer)
      _read_again()
    else
      // Socket shutdown from other side
      // TODO
      return
    end
  
  be _read_again() =>
    """
    Resume reading
    """
    _read()

class TCPConnection
  let fd: U32
  var event: AsioEventID = AsioEvent.none()

  new create(fd': U32) =>
    fd = fd'
