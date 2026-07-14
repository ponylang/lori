use net = "net"

interface LegacyTCPConnection
  """
  A TCP connection with the shape of the standard library `net` package's
  `TCPConnection`, built on top of lori.

  This is the type a `LegacyTCPConnectionNotify` receives as its `conn`
  parameter, and the type an application holds to drive a connection. It is
  reached two ways: create a client with `LegacyTCPClient`, or accept one with
  `LegacyTCPListener`.

  From outside the owning actor only the behaviors (`write`, `writev`, `mute`,
  `unmute`, `set_notify`, `dispose`) can be called. The synchronous methods
  (`close`, `write_final`, `expect`, `local_address`, `remote_address`, and the
  socket-option methods) are for use inside notifier callbacks, where `conn` is
  a `ref`.
  """
  be write(data: ByteSeq)
    """
    Write a single sequence of bytes. Discarded if the connection is not open.
    The `sent` notifier runs first and may transform or swallow the data.
    """

  be writev(data: ByteSeqIter)
    """
    Write several sequences of bytes in one syscall. Discarded if the
    connection is not open. The `sentv` notifier runs first and may transform
    or swallow the data.
    """

  be mute()
    """
    Suspend reading off this connection until `unmute` is called.
    """

  be unmute()
    """
    Resume reading off this connection after `mute`.
    """

  be set_notify(notify: LegacyTCPConnectionNotify iso)
    """
    Replace the notifier.
    """

  be dispose()
    """
    Gracefully close the connection once queued writes are sent. On a muted
    connection this is a hard close that drops undelivered data, the same as
    `close`.
    """

  fun ref write_final(data: ByteSeq)
    """
    Write bytes without running the `sent` notifier. This is the hook a
    protocol wrapper (e.g. `LegacySSLConnection`) uses to push already-encoded
    data. Discarded if the connection is not open.
    """

  fun ref close()
    """
    Gracefully close the connection once queued writes are sent. On a muted
    connection this is a hard close that drops undelivered data.
    """

  fun ref expect(qty: USize = 0) ?
    """
    A `received` call must contain exactly `qty` bytes, or any amount if `qty`
    is zero. No effect when called from the `sent` notifier. Errors if `qty`
    exceeds the read buffer size the connection was created with.
    """

  fun ref set_nodelay(state: Bool)
    """
    Turn Nagle's algorithm on or off. Only meaningful on a connected socket.
    """

  fun ref set_keepalive(secs: U32)
    """
    Set the TCP keepalive timeout to approximately `secs` seconds, or disable
    it with 0. Only meaningful on a connected socket.
    """

  fun ref local_address(): net.NetAddress
    """
    The local IP address. Invalid if the connection is closed.
    """

  fun ref remote_address(): net.NetAddress
    """
    The remote IP address. Invalid if the connection is closed.
    """

  fun ref getsockopt(level: I32, option_name: I32, option_max_size: USize = 4)
    : (U32, Array[U8] iso^)
    """
    General `getsockopt(2)` wrapper. See `OSSockOpt` for options.
    """

  fun ref getsockopt_u32(level: I32, option_name: I32): (U32, U32)
    """
    `getsockopt(2)` wrapper where the kernel returns a `U32`.
    """

  fun ref setsockopt(level: I32, option_name: I32, option: Array[U8]): U32
    """
    General `setsockopt(2)` wrapper. Returns 0 on success or `errno`.
    """

  fun ref setsockopt_u32(level: I32, option_name: I32, option: U32): U32
    """
    `setsockopt(2)` wrapper where the kernel expects a `U32`. Returns 0 on
    success or `errno`.
    """

  fun ref get_so_error(): (U32, U32)
    """
    `getsockopt(fd, SOL_SOCKET, SO_ERROR)`.
    """

  fun ref get_so_rcvbuf(): (U32, U32)
    """
    `getsockopt(fd, SOL_SOCKET, SO_RCVBUF)`.
    """

  fun ref get_so_sndbuf(): (U32, U32)
    """
    `getsockopt(fd, SOL_SOCKET, SO_SNDBUF)`.
    """

  fun ref get_tcp_nodelay(): (U32, U32)
    """
    `getsockopt(fd, IPPROTO_TCP, TCP_NODELAY)`.
    """

  fun ref set_so_rcvbuf(bufsize: U32): U32
    """
    `setsockopt(fd, SOL_SOCKET, SO_RCVBUF)`. Returns 0 on success or `errno`.
    """

  fun ref set_so_sndbuf(bufsize: U32): U32
    """
    `setsockopt(fd, SOL_SOCKET, SO_SNDBUF)`. Returns 0 on success or `errno`.
    """

  fun ref set_tcp_nodelay(state: Bool): U32
    """
    `setsockopt(fd, IPPROTO_TCP, TCP_NODELAY)`. Returns 0 on success or `errno`.
    """
