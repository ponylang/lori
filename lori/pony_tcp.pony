use @pony_os_accept[I32](event: AsioEventID)
use @pony_os_connect_tcp[U32](the_actor: AsioEventNotify,
  host: Pointer[U8] tag,
  port: Pointer[U8] tag,
  from: Pointer[U8] tag,
  asio_flags: U32)
use @pony_os_connect_tcp4[U32](the_actor: AsioEventNotify,
  host: Pointer[U8] tag,
  port: Pointer[U8] tag,
  from: Pointer[U8] tag,
  asio_flags: U32)
use @pony_os_connect_tcp6[U32](the_actor: AsioEventNotify,
  host: Pointer[U8] tag,
  port: Pointer[U8] tag,
  from: Pointer[U8] tag,
  asio_flags: U32)
use @pony_os_keepalive[None](fd: U32, secs: U32)
use @pony_os_listen_tcp[AsioEventID](the_actor: AsioEventNotify,
  host: Pointer[U8] tag,
  port: Pointer[U8] tag)
use @pony_os_listen_tcp4[AsioEventID](the_actor: AsioEventNotify,
  host: Pointer[U8] tag,
  port: Pointer[U8] tag)
use @pony_os_listen_tcp6[AsioEventID](the_actor: AsioEventNotify,
  host: Pointer[U8] tag,
  port: Pointer[U8] tag)
use @pony_os_peername[Bool](fd: U32, ip: net.NetAddress ref)
use @pony_os_recv[U8](event: AsioEventID,
  buffer: Pointer[U8] tag,
  size: USize,
  count_out: Pointer[USize])
use @pony_os_socket_close[None](fd: U32)
use @pony_os_socket_shutdown[None](fd: U32)
use @pony_os_sockname[Bool](fd: U32, ip: net.NetAddress ref)
use @pony_os_writev[U8](ev: AsioEventID,
  iov: Pointer[(Pointer[U8] tag, USize)] tag,
  iovcnt: I32,
  count_out: Pointer[USize])
use @pony_os_writev_max[I32]()

use net = "net"

primitive PonyTCP
  fun listen(the_actor: AsioEventNotify,
    host: String,
    port: String,
    ip_version: IPVersion = DualStack)
    : AsioEventID
  =>
    match ip_version
    | IP4 =>
      @pony_os_listen_tcp4(the_actor, host.cstring(), port.cstring())
    | IP6 =>
      @pony_os_listen_tcp6(the_actor, host.cstring(), port.cstring())
    | DualStack =>
      @pony_os_listen_tcp(the_actor, host.cstring(), port.cstring())
    end

  fun accept(event: AsioEventID): I32 =>
    @pony_os_accept(event)

  fun close(fd: U32) =>
    @pony_os_socket_close(fd)

  fun connect(the_actor: AsioEventNotify,
    host: String,
    port: String,
    from: String,
    asio_flags: U32,
    ip_version: IPVersion = DualStack)
    : U32
  =>
    match ip_version
    | IP4 =>
      @pony_os_connect_tcp4(the_actor,
        host.cstring(),
        port.cstring(),
        from.cstring(),
        asio_flags)
    | IP6 =>
      @pony_os_connect_tcp6(the_actor,
        host.cstring(),
        port.cstring(),
        from.cstring(),
        asio_flags)
    | DualStack =>
      @pony_os_connect_tcp(the_actor,
        host.cstring(),
        port.cstring(),
        from.cstring(),
        asio_flags)
    end

  fun keepalive(fd: U32, secs: U32) =>
    @pony_os_keepalive(fd, secs)

  fun peername(fd: U32, ip: net.NetAddress ref): Bool =>
    @pony_os_peername(fd, ip)

  fun receive(event: AsioEventID,
    buffer: Pointer[U8] tag,
    size: USize)
    : (SocketResult, USize)
  =>
    """
    Receive up to `size` bytes into `buffer`. Returns the tri-state socket
    result plus the number of bytes received on `SocketResultOk`. The call is
    synchronous and non-blocking on every platform: `SocketResultRetry` means
    no data was available (`EWOULDBLOCK`/`WSAEWOULDBLOCK`), `SocketResultError`
    means an unrecoverable error or peer close.
    """
    var count: USize = 0
    let result = SocketResultDecoder(
      @pony_os_recv(event, buffer, size, addressof count))
    (result, count)

  fun shutdown(fd: U32) =>
    @pony_os_socket_shutdown(fd)

  fun sockname(fd: U32, ip: net.NetAddress ref): Bool =>
    @pony_os_sockname(fd, ip)

  fun writev(event: AsioEventID, data: Array[ByteSeq] box,
    from: USize, count: USize,
    first_buffer_byte_offset: USize = 0): (SocketResult, USize) ?
  =>
    """
    Send `count` buffers from `data` starting at index `from` via writev.
    Builds the IOV array of `(pointer, size)` entries internally; the runtime
    turns it into `iovec` (POSIX) or `WSABUF` (Windows) as needed.

    `first_buffer_byte_offset` skips bytes in `data(from)` for partial
    write resume.

    Returns the tri-state socket result plus the number of bytes sent on
    `SocketResultOk`. The call is synchronous and non-blocking on every
    platform.
    """
    var bytes_sent: USize = 0
    let iov = Array[(Pointer[U8] tag, USize)](count)
    var i = from
    while i < (from + count) do
      let entry = data(i)?
      if (i == from) and (first_buffer_byte_offset > 0) then
        iov.push((entry.cpointer(first_buffer_byte_offset),
          entry.size() - first_buffer_byte_offset))
      else
        iov.push((entry.cpointer(), entry.size()))
      end
      i = i + 1
    end
    let result = SocketResultDecoder(
      @pony_os_writev(event, iov.cpointer(), count.i32(),
        addressof bytes_sent))
    (result, bytes_sent)

  fun writev_max(): I32 =>
    """
    Maximum number of `(pointer, size)` entries a single writev call may
    carry. `IOV_MAX` on POSIX, 1 on Windows.
    """
    @pony_os_writev_max()
