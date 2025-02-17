use "collections"

type MaxSpawn is (U32 | None)

class TCPListener
  let _host: String
  let _port: String
  let _limit: MaxSpawn
  var _open_connections: SetIs[TCPConnection tag] = _open_connections.create()
  var _paused: Bool = false
  var _event: AsioEventID = AsioEvent.none()
  var _fd: U32 = -1
  var state: TCPConnectionState = Closed
  var _enclosing: (TCPListenerActor ref | None)

  new create(auth: TCPListenAuth, host: String, port: String, enclosing: TCPListenerActor ref, limit: MaxSpawn = None) =>
    _host = host
    _port = port
    _limit = limit
    _enclosing = enclosing
    let event = PonyTCP.listen(enclosing, _host, _port)
    if not event.is_null() then
      _fd = PonyAsio.event_fd(event)
      _event = event
      state = Open
      enclosing._on_listening()
    else
      enclosing._on_listen_failure()
    end

  new none() =>
    _host = ""
    _port = ""
    _limit = None
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

  fun ref _accept(arg: U32 = 0) =>
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
              let opened = e._on_accept(arg)?
              opened._register_spawner(e)
            end

            if not _at_connection_limit() then
              PonyTCP.accept(_event)
            else
              _paused = true
            end
          else
            PonyTCP.close(arg)
          end
        else
          while not _at_connection_limit() do
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
                let opened = e._on_accept(fd)?
                opened._register_spawner(e)
              else
                PonyTCP.close(fd)
              end
            end
          end

          _paused = true
        end
      end
    else
      _Unreachable()
    end

  fun _at_connection_limit(): Bool =>
    match _limit
    | let l: U32 => _open_connections.size() >= l.usize()
    | None => false
    end

  // TODO this should be private but...
  // https://github.com/ponylang/ponyc/issues/4613
  fun ref connection_opened(conn: TCPConnection tag) =>
    _open_connections.set(conn)

  // TODO this should be private but...
  // https://github.com/ponylang/ponyc/issues/4613
  fun ref connection_closed(conn: TCPConnection tag) =>
    _open_connections.unset(conn)
    if _paused and not _at_connection_limit() then
      _paused = false
      _accept()
    end


