trait ServerLifecycleEventReceiver
  fun ref _connection(): TCPConnection

  fun ref _next_lifecycle_event_receiver(): (ServerLifecycleEventReceiver | None)
    """
    If the implementing receiver is wrapping another receiver, return a
    reference to it. If there is no next receiver, return None.

    This is used so we can maintain default implementation for all trait methods
    without having lifecycle events silently getting eaten if a receiver wraps
    another and doesn't implement a method.
    """

  fun ref _on_started() =>
    """
    Called when a server is started.

    This allows for protocols like SSL that have a handshake to hook in and
    do what they do to do before we start reading and writing.
    """
    match _next_lifecycle_event_receiver()
    | let r: ServerLifecycleEventReceiver =>
      r._on_started()
    | None =>
      None
    end

  fun ref _on_closed() =>
    """
    Called when the connection is closed
    """
    match _next_lifecycle_event_receiver()
    | let r: ServerLifecycleEventReceiver =>
      r._on_closed()
    | None =>
      None
    end

  fun ref _on_expect_set(qty: USize): USize =>
    """
    Called when setting the expect amount on the connection.

    You will want to override this if you are using a protocol like SSL where
    the number of incoming bytes differs from what the receiver sees. protocols
    that feature handshakes are an example of this.
    """
    match _next_lifecycle_event_receiver()
    | let r: ServerLifecycleEventReceiver =>
      r._on_expect_set(qty)
    | None =>
      qty
    end

  fun ref _on_received(data: Array[U8] iso) =>
    """
    Called each time data is received on this connection
    """
    match _next_lifecycle_event_receiver()
    | let r: ServerLifecycleEventReceiver =>
      r._on_received(consume data)
    | None =>
      None
    end

  fun ref _on_send(data: ByteSeq): (ByteSeq | None) =>
    """
    Called when data is about to be sent on this connection.
    This allows for protocols like SSL to hook in and modify the outgoing
    data.

    Return None to indicate that no data should be sent.
    """
    match _next_lifecycle_event_receiver()
    | let r: ServerLifecycleEventReceiver =>
      r._on_send(data)
    | None =>
      data
    end

  fun ref _on_throttled() =>
    """
    Called when we start experiencing backpressure
    """
    match _next_lifecycle_event_receiver()
    | let r: ServerLifecycleEventReceiver =>
      r._on_throttled()
    | None =>
      None
    end

  fun ref _on_unthrottled() =>
    """
    Called when backpressure is released
    """
    match _next_lifecycle_event_receiver()
    | let r: ServerLifecycleEventReceiver =>
      r._on_unthrottled()
    | None =>
      None
    end

trait ClientLifecycleEventReceiver
  fun ref _connection(): TCPConnection

  fun ref _next_lifecycle_event_receiver(): (ClientLifecycleEventReceiver | None)
    """
    If the implementing receiver is wrapping another receiver, return a
    reference to it. If there is no next receiver, return None.

    This is used so we can maintain default implementation for all trait methods
    without having lifecycle events silently getting eaten if a receiver wraps
    another and doesn't implement a method.
    """

  fun ref _on_connecting(inflight_connections: U32) =>
    """
    Called if name resolution succeeded for a TCPConnection and we are now
    waiting for a connection to the server to succeed. The count is the number
    of connections we're trying. This callback will be called each time the
    count changes, until a connection is made or _on_connection_failure() is
    called.
    """
    match _next_lifecycle_event_receiver()
    | let r: ClientLifecycleEventReceiver =>
      r._on_connecting(inflight_connections)
    | None =>
      None
    end

  fun ref _on_connected() =>
    """
    Called when a connection is opened
    """
    match _next_lifecycle_event_receiver()
    | let r: ClientLifecycleEventReceiver =>
      r._on_connected()
    | None =>
      None
    end

  fun ref _on_connection_failure() =>
    """
    Called when a connection fails to open
    """
    match _next_lifecycle_event_receiver()
    | let r: ClientLifecycleEventReceiver =>
      r._on_connection_failure()
    | None =>
      None
    end

  fun ref _on_closed() =>
    """
    Called when the connection is closed
    """
    match _next_lifecycle_event_receiver()
    | let r: ClientLifecycleEventReceiver =>
      r._on_closed()
    | None =>
      None
    end

  fun ref _on_expect_set(qty: USize): USize =>
    """
    Called when setting the expect amount on the connection.

    You will want to override this if you are using a protocol like SSL where
    the number of incoming bytes differs from what the receiver sees. protocols
    that feature handshakes are an example of this.
    """
    match _next_lifecycle_event_receiver()
    | let r: ClientLifecycleEventReceiver =>
      r._on_expect_set(qty)
    | None =>
      qty
    end

  fun ref _on_received(data: Array[U8] iso) =>
    """
    Called each time data is received on this connection
    """
    match _next_lifecycle_event_receiver()
    | let r: ClientLifecycleEventReceiver =>
      r._on_received(consume data)
    | None =>
      None
    end

  fun ref _on_send(data: ByteSeq): (ByteSeq | None) =>
    """
    Called when data is about to be sent on this connection.
    This allows for protocols like SSL to hook in and modify the outgoing
    data.

    Return None to indicate that no data should be sent.
    """
    match _next_lifecycle_event_receiver()
    | let r: ClientLifecycleEventReceiver =>
      r._on_send(data)
    | None =>
      data
    end

  fun ref _on_throttled() =>
    """
    Called when we start experiencing backpressure
    """
    match _next_lifecycle_event_receiver()
    | let r: ClientLifecycleEventReceiver =>
      r._on_throttled()
    | None =>
      None
    end

  fun ref _on_unthrottled() =>
    """
    Called when backpressure is released
    """
    match _next_lifecycle_event_receiver()
    | let r: ClientLifecycleEventReceiver =>
      r._on_unthrottled()
    | None =>
      None
    end

type EitherLifecycleEventReceiver is (ServerLifecycleEventReceiver | ClientLifecycleEventReceiver)
