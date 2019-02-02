use @pony_asio_event_create[AsioEventID](owner: AsioEventNotify, fd: U32,
  flags: U32, nsec: U64, noisy: Bool)
use @pony_asio_event_set_writeable[None](event: AsioEventID, writeable: Bool)


primitive PonyASIO
  fun create_event(the_actor: AsioEventNotify, fd: U32): AsioEventID =>
    @pony_asio_event_create(the_actor, fd, AsioEvent.read_write_oneshot(), 0, true)

  fun destroy(event: AsioEventID) =>
    @pony_asio_event_destroy[None](event)

  fun set_writeable(event: AsioEventID) =>
    @pony_asio_event_set_writeable(event, true)
