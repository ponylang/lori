interface tag TCPListenerActor
  fun ref self(): TCPListener

  fun ref on_accept(state: TCPConnection iso): TCPConnectionActor
    """
    Called when a connection is accepted
    """

  fun ref on_closed()
    """
    Called after the listener is closed
    """

  fun ref on_listening()
    """
    Called once the listener is ready to accept connections
    """

  be dispose() =>
    """
    Stop listening
    """
    close()

  be _event_notify(event: AsioEventID, flags: U32, arg: U32) =>
    if event isnt self().event then
      return
    end

    if AsioEvent.readable(flags) then
      _accept(arg)
    end

    if AsioEvent.disposable(flags) then
      self().dispose_event()
      self().event = AsioEvent.none()
    end 

  fun ref close() =>
    if self().state is Open then
      self().state = Closed

      if not self().event.is_null() then
        PonyASIO.unsubscribe(self().event)
        PonyTCP.close(self().fd)
        self().fd = -1
        on_closed()
      end
    end

  fun ref open() =>
    if self().state is Closed then
      let event = PonyTCP.listen(this, self().host, self().port)
      if not event.is_null() then
        self().fd = PonyASIO.event_fd(event)
        self().event = event
       self().state = Open
       on_listening()
     end
   else
     ifdef debug then
       FatalUserError("open() called on already open TCPListener.")
     end
   end

  fun ref _accept(arg: U32) =>
    match self().state
    | Closed => 
      // It's possible that after closing, we got an event for a connection
      // attempt. If that is the case or the listener is otherwise not open,
      // return and do not start a new connection
      return
    | Open => 
      var fd = PonyTCP.accept(self().event)
      
      match fd
      | -1 =>
        // TODO: handle 
        return
      | 0 =>
        // TODO: handle
        return
      else
        _start_connection(fd)
      end
    end 

  fun ref _start_connection(fd: U32) =>
    """
    Start a new connection to handle this incoming connection.
    """
    let state: TCPConnection iso = recover iso TCPConnection.server(fd) end
    let connection = on_accept(consume state)
    connection.open()

class TCPListener
  let host: String
  let port: String
  var event: AsioEventID = AsioEvent.none()
  var fd: U32 = -1
  var state: TCPConnectionState = Closed

  new create(host': String, port': String) =>
    host = host'
    port = port'

  fun ref dispose_event() =>
    PonyASIO.destroy(event)
    event = AsioEvent.none()
    state = Closed

