use "collections"

class TCPConnection
  var fd: U32
  var event: AsioEventID = AsioEvent.none()
  var _state: U32 = 0
  let _pending: List[(ByteSeq, USize)] = _pending.create()

  new client() =>
    fd = -1

  new server(fd': U32) =>
    fd = fd'

  fun ref close() =>
    if is_open() then
      _state = BitSet.unset(_state, 0)
      unwriteable()
      PonyTCP.shutdown(fd)
      PonyASIO.unsubscribe(event)
      fd = -1
    end

  fun is_closed(): Bool =>
    not is_open()

  fun is_open(): Bool =>
    BitSet.is_set(_state, 0)

  fun ref open() =>
    _state = BitSet.set(_state, 0)
    writeable()

  fun is_writeable(): Bool =>
    BitSet.is_set(_state, 1)

  fun ref writeable() =>
    _state = BitSet.set(_state, 1)

  fun ref unwriteable() =>
    _state = BitSet.unset(_state, 1)

  fun is_throttled(): Bool =>
    BitSet.is_set(_state, 2)

  fun ref throttled() =>
    _state = BitSet.set(_state, 2)
    // throttled means we are also unwriteable
    // being unthrottled doesn't however mean we are writable
    unwriteable()
    PonyASIO.set_unwriteable(event)

  fun ref unthrottled() =>
    _state = BitSet.unset(_state, 2)

  fun has_pending_writes(): Bool =>
    _pending.size() != 0

  fun ref add_pending_data(data: ByteSeq, offset: USize) =>
    _pending.push((data, offset))

  fun ref pending_head(): ListNode[(ByteSeq, USize)] ? =>
    _pending.head()?

  fun ref pending_shift(): (ByteSeq, USize) ? =>
    _pending.shift()?

/* maybe move _send_pending_writes here

  pros:
    - encapsulate pending data usage
    - would move most backpressure logic into here where it
      probably belongs

  cons:
    - TPCConnection needs to know about enclosing actor or it
      needs to have return type for change in backpressure
    - With PonyTCP called from in here, we'd need to make both this class
      and the actor interface generic and over the same thing that
      implements PonyTCP once we start allowing that to be specialized.

      However, we are already doing that by using PonyASIO in here, although,
      I have no plans at this time to allow that to be specialized, except,
      it could be useful for testing to make it so.


  fun ref send_pending_writes() =>
    while is_writeable() and has_pending_writes() do
      try
        let node = _pending.head()?
        (let data, let offset) = node()?

        let len = PonyTCP.send(self().event, data, offset)?

        if (len + offset) < data.size() then
          // not all data was sent
          node()? = (data, offset + len)
          _apply_backpressure()
        else
          _pending.shift()?
        end
      else
        // error sending. appears our connection has been shutdown.
        // TODO: handle close here
        None
      end
    end

    if pending_writes() then
      // all pending data was sent
      _release_backpressure()
    end
*/
