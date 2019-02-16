class TCPListener
  let host: String
  let port: String
  var event: AsioEventID = AsioEvent.none()
  var fd: U32 = -1
  var state: TCPConnectionState = Closed
  var _enclosing: (TCPListenerActor ref | None)

  new create(host': String, port': String, enclosing: TCPListenerActor ref) =>
    host = host'
    port = port'
    _enclosing = enclosing

  new none() =>
    host = ""
    port = ""
    _enclosing = None

  fun ref dispose_event() =>
    PonyASIO.destroy(event)
    event = AsioEvent.none()
    state = Closed

  fun ref close() =>
    match _enclosing
    | let e: TCPListenerActor ref =>
      if state is Open then
        state = Closed

        if not event.is_null() then
          PonyASIO.unsubscribe(event)
          PonyTCP.close(fd)
          fd = -1
          e.on_closed()
        end
      end
    | None =>
      // TODO: blow up here, deal with this
      None
    end
