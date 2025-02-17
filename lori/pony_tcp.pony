use @pony_os_accept[U32](event: AsioEventID)
use @pony_os_connect_tcp[U32](the_actor: AsioEventNotify,
  host: Pointer[U8] tag,
  port: Pointer[U8] tag,
  from: Pointer[U8] tag,
  asio_flags: U32)
use @pony_os_keepalive[None](fd: U32, secs: U32)
use @pony_os_listen_tcp[AsioEventID](the_actor: AsioEventNotify,
  host: Pointer[U8] tag,
  port: Pointer[U8] tag)
use @pony_os_peername[Bool](fd: U32, ip: net.NetAddress tag)
use @pony_os_recv[USize](event: AsioEventID,
  buffer: Pointer[U8] tag,
  offset: USize) ?
use @pony_os_send[USize](event: AsioEventID,
  buffer: Pointer[U8] tag,
  from_offset: USize) ?
use @pony_os_socket_close[None](fd: U32)
use @pony_os_socket_shutdown[None](fd: U32)
use @pony_os_sockname[Bool](fd: U32, ip: net.NetAddress tag)

use net = "net"

primitive PonyTCP
  fun listen(the_actor: AsioEventNotify,
    host: String,
    port: String)
    : AsioEventID
  =>
    @pony_os_listen_tcp(the_actor, host.cstring(), port.cstring())

  fun accept(event: AsioEventID): U32 =>
    @pony_os_accept(event)

  fun close(fd: U32) =>
    @pony_os_socket_close(fd)

  fun connect(the_actor: AsioEventNotify,
    host: String,
    port: String,
    from: String,
    asio_flags: U32)
    : U32
  =>
    @pony_os_connect_tcp(the_actor,
      host.cstring(),
      port.cstring(),
      from.cstring(),
      asio_flags)

  fun keepalive(fd: U32, secs: U32) =>
    @pony_os_keepalive(fd, secs)

  fun peername(fd: U32, ip: net.NetAddress tag): Bool =>
    @pony_os_peername(fd, ip)

  fun receive(event: AsioEventID,
    buffer: Pointer[U8] tag,
    offset: USize)
    : USize ?
  =>
    @pony_os_recv(event, buffer, offset)?

  fun send(event: AsioEventID,
    buffer: ByteSeq,
    from_offset: USize = 0)
    : USize ?
  =>
    @pony_os_send(event,
      buffer.cpointer(from_offset),
      buffer.size() - from_offset)?

  fun shutdown(fd: U32) =>
    @pony_os_socket_shutdown(fd)

  fun sockname(fd: U32, ip: net.NetAddress tag): Bool =>
    @pony_os_sockname(fd, ip)
