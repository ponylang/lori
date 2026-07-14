use net = "net"
use "constrained_types"

trait _LegacyConnection is LegacyTCPConnection
  """
  Shared implementation of the `LegacyTCPConnection` surface for the client and
  accepted-connection actors. Each actor supplies the accessors below; this
  trait turns them into the stdlib-shaped connection methods, delegating the
  actual I/O to the lori `TCPConnection` the actor owns.
  """
  fun ref _connection(): TCPConnection
  fun ref _notifier(): LegacyTCPConnectionNotify
  fun ref _set_notifier(notify: LegacyTCPConnectionNotify)
  fun ref _sending(): Bool
  fun ref _set_sending(value: Bool)
  fun ref _read_buffer_size(): USize
  fun ref _read_state(): _LegacyReadState

  fun ref _deliver_received(data: Array[U8] iso): ReadAction =>
    """
    Deliver received data to the notifier and decide whether to yield the read
    loop. Yields on the notifier returning `false`, after 50 deliveries since
    the last yield, or once the bytes since the last yield reach
    `yield_after_reading`. Shared by both connection actors so the yield policy
    lives in one place.
    """
    let rs = _read_state()
    rs.count = rs.count + 1
    rs.bytes = rs.bytes + data.size()
    let keep = _notifier().received(this, consume data, rs.count)
    if (not keep) or (rs.count >= 50) or (rs.bytes >= rs.yield_after) then
      rs.count = 0
      rs.bytes = 0
      YieldReading
    else
      KeepReading
    end

  be write(data: ByteSeq) =>
    if _connection().is_open() then
      _set_sending(true)
      let out = _notifier().sent(this, data)
      _set_sending(false)
      if out.size() > 0 then
        _connection().send(out)
      end
    end

  be writev(data: ByteSeqIter) =>
    if _connection().is_open() then
      _set_sending(true)
      let out = _notifier().sentv(this, data)
      _set_sending(false)
      // No empty-swallow guard as in `write`: `ByteSeqIter` has no safe
      // emptiness check, and lori's `send` already skips empty buffers.
      _connection().send(out)
    end

  fun ref write_final(data: ByteSeq) =>
    if _connection().is_open() then
      _connection().send(data)
    end

  be mute() =>
    _connection().mute()

  be unmute() =>
    _connection().unmute()

  be set_notify(notify: LegacyTCPConnectionNotify iso) =>
    _set_notifier(consume notify)

  fun ref close() =>
    _connection().close()

  fun ref expect(qty: USize = 0) ? =>
    if qty > _read_buffer_size() then
      error
    end

    if not _sending() then
      let e = _notifier().expect(this, qty)
      if e == 0 then
        match \exhaustive\ _connection().buffer_until(Streaming)
        | BufferUntilSet => None
        | BufferSizeAboveMinimum => _Unreachable()
        end
      else
        // A notifier can return a frame larger than the read buffer holds
        // (nested framing changes the quantity). Bound the frame to the read
        // buffer size -- the same ceiling the `qty` check above enforces --
        // rather than growing the buffer to an unbounded, possibly
        // attacker-supplied, value.
        let frame = e.min(_read_buffer_size())
        match \exhaustive\ MakeBufferSize(frame)
        | let b: BufferSize =>
          match \exhaustive\ _connection().buffer_until(b)
          | BufferUntilSet => None
          | BufferSizeAboveMinimum => _Unreachable()
          end
        | let _: ValidationFailure =>
          // frame >= 1 (e > 0 and _read_buffer_size() >= 1), so this can't
          // fail.
          _Unreachable()
        end
      end
    end

  fun ref set_nodelay(state: Bool) =>
    _connection().set_nodelay(state)

  fun ref set_keepalive(secs: U32) =>
    _connection().keepalive(secs)

  fun ref local_address(): net.NetAddress =>
    _connection().local_address()

  fun ref remote_address(): net.NetAddress =>
    _connection().remote_address()

  fun ref getsockopt(level: I32, option_name: I32, option_max_size: USize = 4)
    : (U32, Array[U8] iso^)
  =>
    _connection().getsockopt(level, option_name, option_max_size)

  fun ref getsockopt_u32(level: I32, option_name: I32): (U32, U32) =>
    _connection().getsockopt_u32(level, option_name)

  fun ref setsockopt(level: I32, option_name: I32, option: Array[U8]): U32 =>
    _connection().setsockopt(level, option_name, option)

  fun ref setsockopt_u32(level: I32, option_name: I32, option: U32): U32 =>
    _connection().setsockopt_u32(level, option_name, option)

  fun ref get_so_error(): (U32, U32) =>
    _connection().getsockopt_u32(OSSockOpt.sol_socket(), OSSockOpt.so_error())

  fun ref get_so_rcvbuf(): (U32, U32) =>
    _connection().get_so_rcvbuf()

  fun ref get_so_sndbuf(): (U32, U32) =>
    _connection().get_so_sndbuf()

  fun ref get_tcp_nodelay(): (U32, U32) =>
    _connection().getsockopt_u32(
      OSSockOpt.ipproto_tcp(), OSSockOpt.tcp_nodelay())

  fun ref set_so_rcvbuf(bufsize: U32): U32 =>
    _connection().set_so_rcvbuf(bufsize)

  fun ref set_so_sndbuf(bufsize: U32): U32 =>
    _connection().set_so_sndbuf(bufsize)

  fun ref set_tcp_nodelay(state: Bool): U32 =>
    _connection().set_nodelay(state)
