primitive PonyTCP
  fun listen(the_actor: AsioEventNotify, host: String, port: String): AsioEventID =>
    @pony_os_listen_tcp[AsioEventID](the_actor, host.cstring(), port.cstring())

  fun accept(event: AsioEventID): U32 =>
    @pony_os_accept[U32](event)

  fun connect(the_actor: AsioEventNotify, host: String, port: String, from: String): U32 =>
    @pony_os_connect_tcp[U32](the_actor, host.cstring(), port.cstring(), from.cstring())

  fun receive(event: AsioEventID, buffer: Pointer[U8] tag, offset: USize): USize ? =>
    @pony_os_recv[USize](event, buffer, offset)?

  fun send(event: AsioEventID, buffer: ByteSeq, buffer_len: USize): USize =>
    // this can throw an error
    let sent = @pony_os_send[USize](event, buffer.cpointer(), buffer_len)
    @printf[I32]("%d bytes sent\n".cstring(), sent)
    sent
