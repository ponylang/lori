class TCPListener
  let host: String
  let port: String
  var _event: AsioEventID = AsioEvent.none()
  var _fd: U32 = -1
  var state: TCPConnectionState = Closed
  var _enclosing: (TCPListenerActor ref | None)

  new create(host': String, port': String, enclosing: TCPListenerActor ref) =>
    host = host'
    port = port'
    _enclosing = enclosing
    open()

  new none() =>
    host = ""
    port = ""
    _enclosing = None

  fun ref open() =>
    match _enclosing
    | let e: TCPListenerActor ref =>
      if state is Closed then
        let event = PonyTCP.listen(e, host, port)
        if not event.is_null() then
          _fd = PonyASIO.event_fd(event)
          _event = event
          state = Open
          e.on_listening()
        else
          e.on_failure()
        end
      else
        ifdef debug then
          FatalUserError("Open called on already open TCPListener.")
        end
      end
    | None =>
      // TODO: blow up here
      None
    end

  fun ref close() =>
    match _enclosing
    | let e: TCPListenerActor ref =>
      if state is Open then
        state = Closed

        if not _event.is_null() then
          PonyASIO.unsubscribe(_event)
          PonyTCP.close(_fd)
          _fd = -1
          e.on_closed()
        end
      end
    | None =>
      // TODO: blow up here, deal with this
      None
    end

  fun ref event_notify(event: AsioEventID, flags: U32, arg: U32) =>
    if event isnt _event then
      return
    end

    if AsioEvent.readable(flags) then
      _accept(arg)
    end

    if AsioEvent.disposable(flags) then
      PonyASIO.destroy(_event)
      _event = AsioEvent.none()
      state = Closed
    end

  fun ref _accept(arg: U32) =>
    match _enclosing
    | let e: TCPListenerActor ref =>
      match state
      | Closed =>
        // It's possible that after closing, we got an event for a connection
        // attempt. If that is the case or the listener is otherwise not open,
        // return and do not start a new connection
        return
      | Open =>
        while true do
          var fd = PonyTCP.accept(_event)

          match fd
            | -1 =>
            // Wouldn't block but we got an error. Keep trying.
            None
            | 0 =>
            // Would block. Bail out.
            return
          else
            e.on_accept(fd)
            return
          end
        end
      end
    | None =>
      // TODO: blow up here!
      None
    end
