trait tag TCPClientActor is TCPConnectionActor
  fun ref _on_connected() =>
    """
    Called when a connection is opened
    """
    None

  fun ref _on_connection_failure() =>
    """
    Called when a connection fails to open
    """
    None

trait tag TCPServerActor is TCPConnectionActor

trait tag TCPConnectionActor is AsioEventNotify
  fun ref _connection(): TCPConnection

  fun ref _on_closed() =>
    """
    Called when the connection is closed
    """
    None

  fun ref _on_received(data: Array[U8] iso) =>
    """
    Called each time data is received on this connection
    """
    None

  fun ref _on_throttled() =>
    """
    Called when we start experiencing backpressure
    """
    None

  fun ref _on_unthrottled() =>
    """
    Called when backpressure is released
    """
    None

  be dispose() =>
    """
    Close connection
    """
    _connection().close()

  be _event_notify(event: AsioEventID, flags: U32, arg: U32) =>
    _connection().event_notify(event, flags, arg)

  be _read_again() =>
    """
    Resume reading
    """
    _connection().read()
