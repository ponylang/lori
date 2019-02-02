primitive PonyTCP
  fun listen(the_actor: AsioEventNotify, host: String, port: String): AsioEventID =>
    @pony_os_listen_tcp[AsioEventID](the_actor, host.cstring(), port.cstring())

  fun accept(event: AsioEventID): U32 =>
     @pony_os_accept[U32](event)

