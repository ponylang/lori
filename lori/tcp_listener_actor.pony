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
    self().close()

  be _event_notify(event: AsioEventID, flags: U32, arg: U32) =>
    self().event_notify(event, flags, arg)
