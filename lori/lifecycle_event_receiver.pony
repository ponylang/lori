trait ServerLifecycleEventReceiver
  """
  Application-level callbacks for server-side TCP connections.
  One receiver per connection, no chaining.
  """
  fun ref _connection(): TCPConnection

  fun ref _on_started() =>
    """
    Called when a server connection is ready for application data.
    """
    None

  fun ref _on_closed() =>
    """
    Called when the connection is closed.
    """
    None

  fun ref _on_received(data: Array[U8] iso) =>
    """
    Called each time data is received on this connection.
    """
    None

  fun ref _on_throttled() =>
    """
    Called when we start experiencing backpressure.
    """
    None

  fun ref _on_unthrottled() =>
    """
    Called when backpressure is released.
    """
    None

trait ClientLifecycleEventReceiver
  """
  Application-level callbacks for client-side TCP connections.
  One receiver per connection, no chaining.
  """
  fun ref _connection(): TCPConnection

  fun ref _on_connecting(inflight_connections: U32) =>
    """
    Called if name resolution succeeded for a TCPConnection and we are now
    waiting for a connection to the server to succeed. The count is the number
    of connections we're trying. This callback will be called each time the
    count changes, until a connection is made or _on_connection_failure() is
    called.
    """
    None

  fun ref _on_connected() =>
    """
    Called when a connection is ready for application data.
    """
    None

  fun ref _on_connection_failure() =>
    """
    Called when a connection fails to open. For connections with a
    DataInterceptor, this is also called when the connection closes during
    the interceptor's handshake phase (before signal_ready), since the
    application was never notified of the connection.
    """
    None

  fun ref _on_closed() =>
    """
    Called when the connection is closed.
    """
    None

  fun ref _on_received(data: Array[U8] iso) =>
    """
    Called each time data is received on this connection.
    """
    None

  fun ref _on_throttled() =>
    """
    Called when we start experiencing backpressure.
    """
    None

  fun ref _on_unthrottled() =>
    """
    Called when backpressure is released.
    """
    None

type EitherLifecycleEventReceiver is
  (ServerLifecycleEventReceiver | ClientLifecycleEventReceiver)
