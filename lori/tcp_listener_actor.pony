trait tag TCPListenerActor is AsioEventNotify
  fun ref listener(): TCPListener

  fun ref on_accept(fd: U32): TCPConnectionActor
    """
    Called when a connection is accepted
    """

  fun ref on_closed() =>
    """
    Called after the listener is closed
    """
    None

  fun ref on_connection_failure() =>
    """
    Called if we are unable to open the listener
    """
    None

  fun ref on_listening() =>
    """
    Called once the listener is ready to accept connections
    """
    None

  be dispose() =>
    """
    Stop listening
    """
    listener().close()

  be _event_notify(event: AsioEventID, flags: U32, arg: U32) =>
    listener().event_notify(event, flags, arg)
