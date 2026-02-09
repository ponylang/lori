trait tag TCPConnectionActor is AsioEventNotify
  fun ref _connection(): TCPConnection

  be dispose() =>
    """
    Close connection
    """
    _connection().close()

  be _event_notify(event: AsioEventID, flags: U32, arg: U32) =>
    _connection()._event_notify(event, flags, arg)

  be _read_again() =>
    """
    Resume reading
    """
    ifdef posix then
      _connection()._read()
    end

  be _register_spawner(listener: TCPListenerActor) =>
    """
    Register the listener as the spawner of this connection
    """
    _connection()._register_spawner(listener)

  be _notify_sent(token: SendToken) =>
    """
    Deferred delivery of _on_sent to the lifecycle event receiver.
    """
    _connection()._fire_on_sent(token)

  be _finish_initialization() =>
    _connection()._finish_initialization()
