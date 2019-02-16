interface tag TCPListenerActor
  fun ref self(): TCPListener

  fun ref on_accept(fd: U32): TCPConnectionActor
    """
    Called when a connection is accepted
    """

  fun ref on_closed()
    """
    Called after the listener is closed
    """

  fun ref on_failure()
    """
    Called if we are unable to open the listener
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


  fun ref open() =>
    if self().state is Closed then
      let event = PonyTCP.listen(this, self().host, self().port)
      if not event.is_null() then
        self().fd = PonyASIO.event_fd(event)
        self().event = event
        self().state = Open
        on_listening()
      else
        on_failure()
      end
    else
      ifdef debug then
        FatalUserError("Open called on already open TCPListener.")
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
      while true do
        var fd = PonyTCP.accept(self().event)

        match fd
        | -1 =>
          // Wouldn't block but we got an error. Keep trying.
          None
        | 0 =>
          // Would block. Bail out.
          return
        else
          on_accept(fd)
          return
        end
      end
    end
