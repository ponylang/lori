use net = "net"

trait val TCPBackend
  """
  The TCP operations a connection and listener need from the runtime.
  `RuntimeBackend` is the production implementation; test code can
  substitute a fake to drive the connection state machine without
  real sockets.
  """
  new val create()

  fun listen(the_actor: AsioEventNotify,
    host: String,
    port: String,
    ip_version: IPVersion = DualStack)
    : AsioEventID
    """
    Open a listening socket bound to `host`:`port` and subscribe
    `the_actor` for accept-readiness events. Returns the ASIO event,
    or a null event on failure.
    """

  fun accept(event: AsioEventID): I32
    """
    Accept one pending connection on the listening socket behind
    `event`. Returns the fd (> 0), 0 if none is ready, or -1 on
    error.
    """

  fun close(fd: U32)
    """
    Close the socket.
    """

  fun connect(the_actor: AsioEventNotify,
    host: String,
    port: String,
    from: String,
    asio_flags: U32,
    ip_version: IPVersion = DualStack)
    : U32
    """
    Start non-blocking TCP connection attempts to `host`:`port`.
    Returns the number of attempts started (one per resolved
    address). Zero means every attempt failed immediately.
    """

  fun keepalive(fd: U32, secs: U32)
    """
    Enable TCP keepalive on `fd` with an interval of `secs` seconds.
    """

  fun peername(fd: U32, ip: net.NetAddress ref): Bool
    """
    Fill `ip` with the remote address of `fd`. Returns true on
    success.
    """

  fun receive(event: AsioEventID,
    buffer: Pointer[U8] tag,
    size: USize)
    : (SocketResult, USize)
    """
    Receive up to `size` bytes into `buffer`. The call is synchronous
    and non-blocking: `SocketResultRetry` means no data was
    available, `SocketResultError` means an unrecoverable error or
    peer close.
    """

  fun shutdown(fd: U32)
    """
    Shut down the write side of `fd`.
    """

  fun sockname(fd: U32, ip: net.NetAddress ref): Bool
    """
    Fill `ip` with the local address of `fd`. Returns true on
    success.
    """

  fun sendv(event: AsioEventID,
    data: Array[ByteSeq] box,
    from: USize,
    count: USize,
    first_buffer_byte_offset: USize = 0)
    : (SocketResult, USize) ?
    """
    Send `count` buffers from `data` starting at index `from`.
    Returns the tri-state socket result plus the number of bytes
    sent on `SocketResultOk`. The call is synchronous and
    non-blocking.
    """

  fun writev_max(): I32
    """
    Maximum number of buffers a single `sendv` call may carry.
    """
