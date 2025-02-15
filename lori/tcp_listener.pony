class TCPListener
  let host: String
  let port: String
  var _event: AsioEventID = AsioEvent.none()
  var _fd: U32 = -1
  var state: TCPConnectionState = Closed
  var _enclosing: (TCPListenerActor ref | None)

  new create(auth: TCPListenAuth, host': String, port': String, enclosing: TCPListenerActor ref) =>
    host = host'
    port = port'
    _enclosing = enclosing
    let event = PonyTCP.listen(enclosing, host, port)
    if not event.is_null() then
      _fd = PonyAsio.event_fd(event)
      _event = event
      state = Open
      enclosing._on_listening()
    else
      enclosing._on_listen_failure()
    end

  new none() =>
    host = ""
    port = ""
    _enclosing = None

  fun ref close() =>
    match _enclosing
    | let e: TCPListenerActor ref =>
      // TODO: when in debug mode we should blow up if listener is closed
      if state is Open then
        state = Closed

        if not _event.is_null() then
          PonyAsio.unsubscribe(_event)
          PonyTCP.close(_fd)
          _fd = -1
          e.on_closed()
        end
      end
    else
      _Unreachable()
    end

  fun ref event_notify(event: AsioEventID, flags: U32, arg: U32) =>
    if event isnt _event then
      return
    end

    if AsioEvent.readable(flags) then
      _accept(arg)
    end

    if AsioEvent.disposable(flags) then
      PonyAsio.destroy(_event)
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
        ifdef windows then
          if arg == -1 then
            PonyAsio.unsubscribe(_event)
            return
          end

          if arg > 0 then
            PonyTCP.close(arg)
          end
        end
        return
      | Open =>
        ifdef windows then
          // Unsubscribe if we get an invalid socket in an event
          if arg == -1 then
            PonyAsio.unsubscribe(_event)
            return
          end

          try
            if arg > 0 then
              e._on_accept(arg)?
            end

            PonyTCP.accept(_event)
          else
            PonyTCP.close(arg)
          end
        else
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
              try
                e._on_accept(fd)?
              else
                PonyTCP.close(fd)
              end
            end
          end
        end
      end
    else
      _Unreachable()
    end
