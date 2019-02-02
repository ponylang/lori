trait val TCPListenerConnectionState

primitive Open is TCPListenerConnectionState
primitive Closed is TCPListenerConnectionState

interface tag TCPListenerActor
  fun ref self(): TCPListener

  fun on_accept(state: TCPConnection iso): TCPConnectionActor
    """
    Called when a connection is accepted
    """

  be _event_notify(event: AsioEventID, flags: U32, arg: U32) =>
    if event isnt self().event then
      return
    end

    if AsioEvent.readable(flags) then
      _accept(arg)
    end

    if AsioEvent.disposable(flags) then
      self().dispose_event()
    end 

  fun ref open() =>
    // should check to make sure listener is closed
    let event = PonyTCP.listen(this, self().host, self().port)
    if not event.is_null() then
      self().event = event
      self().state = Open
    end

  fun ref _accept(arg: U32) =>
    match self().state
    | Closed => return
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
    let state: TCPConnection iso = recover iso TCPConnection(fd) end
    let connection = on_accept(consume state)
    connection.open()

class TCPListener
  let host: String
  let port: String
  var event: AsioEventID = AsioEvent.none()
  var state: TCPListenerConnectionState = Closed

  new create(host': String, port': String) =>
    host = host'
    port = port'

  fun ref dispose_event() =>
    PonyASIO.destroy(event)
    event = AsioEvent.none()
    state = Closed

