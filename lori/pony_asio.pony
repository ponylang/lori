use @pony_asio_event_create[AsioEventID](owner: AsioEventNotify, fd: U32,
  flags: U32, nsec: U64, noisy: Bool)
use @pony_asio_event_destroy[None](event: AsioEventID)
use @pony_asio_event_fd[U32](event: AsioEventID)
use @pony_asio_event_get_disposable[Bool](event: AsioEventID)
use @pony_asio_event_resubscribe_read[None](event: AsioEventID)
use @pony_asio_event_resubscribe_write[None](event: AsioEventID)
use @pony_asio_event_set_readable[None](event: AsioEventID, readable: Bool)
use @pony_asio_event_set_writeable[None](event: AsioEventID, writeable: Bool)
use @pony_asio_event_unsubscribe[None](event: AsioEventID)

primitive PonyAsio
  fun create_event(the_actor: AsioEventNotify, fd: U32): AsioEventID =>
    let asio_flags = ifdef windows then
      AsioEvent.read_write()
    else
      AsioEvent.read_write_oneshot()
    end

    @pony_asio_event_create(the_actor, fd, asio_flags, 0, true)

  fun destroy(event: AsioEventID) =>
    @pony_asio_event_destroy(event)

  fun event_fd(event: AsioEventID): U32 =>
    @pony_asio_event_fd(event)

  fun get_disposable(event: AsioEventID): Bool =>
    @pony_asio_event_get_disposable(event)

  fun resubscribe_read(event: AsioEventID) =>
    @pony_asio_event_resubscribe_read(event)

  fun resubscribe_write(event: AsioEventID) =>
    @pony_asio_event_resubscribe_write(event)

  fun set_readable(event: AsioEventID) =>
    @pony_asio_event_set_readable(event, true)

  fun set_unreadable(event: AsioEventID) =>
    @pony_asio_event_set_readable(event, false)

  fun set_writeable(event: AsioEventID) =>
    @pony_asio_event_set_writeable(event, true)

  fun set_unwriteable(event: AsioEventID) =>
    @pony_asio_event_set_writeable(event, false)

  fun unsubscribe(event: AsioEventID) =>
    @pony_asio_event_unsubscribe(event)
