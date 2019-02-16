interface tag TCPConnectionActor
  fun ref self(): TCPConnection

  fun ref on_closed()
    """
    Called when the connection is closed
    """

  fun ref on_connected()
    """
    Called when a connection is opened
    """

  fun ref on_received(data: Array[U8] iso)
    """
    Called each time data is received on this connection
    """

  fun ref on_throttled() =>
    """
    Called when we start experiencing backpressure
    """

    None

  fun ref on_unthrottled() =>
    """
    Called when backpressure is released
    """

    None

  be dispose() =>
    """
    Close connection
    """
    self().close()

  be _event_notify(event: AsioEventID, flags: U32, arg: U32) =>
    self().event_notify(this, event, flags, arg)

  be _read_again() =>
    """
    Resume reading
    """
    self().read(this)
