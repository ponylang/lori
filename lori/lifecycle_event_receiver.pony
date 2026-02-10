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

  fun ref _on_sent(token: SendToken) =>
    """
    Called when data from a successful send() has been fully handed to the
    OS. The token matches the one returned by send().

    Always fires in a subsequent behavior turn, never synchronously during
    send(). This guarantees the caller has received and processed the
    SendToken return value before the callback arrives.
    """
    None

  fun ref _on_send_failed(token: SendToken) =>
    """
    Called when data from a successful send() could not be delivered to the
    OS. The token matches the one returned by send(). This happens when a
    connection closes while a partial write is still pending.

    Always fires in a subsequent behavior turn, never synchronously during
    hard_close(). Always arrives after _on_closed, which fires synchronously
    during hard_close().
    """
    None

  fun ref _on_start_failure() =>
    """
    Called when a server connection fails to start. This covers failures
    that occur before _on_started would have fired, such as an SSL
    handshake failure. The application was never notified of the connection
    via _on_started.
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
    Called when a connection fails to open. For SSL connections, this is
    also called when the SSL handshake fails before _on_connected would
    have been delivered, since the application was never notified of the
    connection.
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

  fun ref _on_sent(token: SendToken) =>
    """
    Called when data from a successful send() has been fully handed to the
    OS. The token matches the one returned by send().

    Always fires in a subsequent behavior turn, never synchronously during
    send(). This guarantees the caller has received and processed the
    SendToken return value before the callback arrives.
    """
    None

  fun ref _on_send_failed(token: SendToken) =>
    """
    Called when data from a successful send() could not be delivered to the
    OS. The token matches the one returned by send(). This happens when a
    connection closes while a partial write is still pending.

    Always fires in a subsequent behavior turn, never synchronously during
    hard_close(). Always arrives after _on_closed, which fires synchronously
    during hard_close().
    """
    None

type EitherLifecycleEventReceiver is
  (ServerLifecycleEventReceiver | ClientLifecycleEventReceiver)
