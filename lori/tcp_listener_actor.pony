trait tag TCPListenerActor is AsioEventNotify
  fun ref _listener(): TCPListener

  fun ref _on_accept(fd: U32): TCPConnectionActor ?
    """
    Called when a connection is accepted
    """

  fun ref _on_closed() =>
    """
    Called after the listener is closed
    """
    None

  fun ref _on_listen_failure() =>
    """
    Called if we are unable to open the listener
    """
    None

  fun ref _on_listening() =>
    """
    Called once the listener is ready to accept connections
    """
    None

  be dispose() =>
    """
    Stop listening
    """
    _listener().close()

  be _event_notify(event: AsioEventID, flags: U32, arg: U32) =>
    // `arg` is part of the runtime AsioEventNotify interface; the listener
    // does not use it (it carried the IOCP accept fd under the old backend).
    _listener()._event_notify(event, flags)

  be _connection_closed() =>
    _listener()._connection_closed()

  be _finish_initialization() =>
    _listener()._finish_initialization()
