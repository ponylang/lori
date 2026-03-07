use "ssl/net"

trait _ConnectionState
  fun ref own_event(conn: TCPConnection ref, flags: U32, arg: U32)
  fun ref foreign_event(conn: TCPConnection ref, event: AsioEventID,
    flags: U32, arg: U32)
  fun ref send(conn: TCPConnection ref,
    data: (ByteSeq | ByteSeqIter)): (SendToken | SendError)
  fun ref close(conn: TCPConnection ref)
  fun ref hard_close(conn: TCPConnection ref)
  fun ref start_tls(conn: TCPConnection ref, ssl_ctx: SSLContext val,
    host: String): (None | StartTLSError)
  fun ref read_again(conn: TCPConnection ref)
  fun is_open(): Bool
  fun is_closed(): Bool

class _ConnectionNone is _ConnectionState
  fun ref own_event(conn: TCPConnection ref, flags: U32, arg: U32) =>
    _Unreachable()

  fun ref foreign_event(conn: TCPConnection ref, event: AsioEventID,
    flags: U32, arg: U32)
  =>
    _Unreachable()

  fun ref send(conn: TCPConnection ref,
    data: (ByteSeq | ByteSeqIter)): (SendToken | SendError)
  =>
    _Unreachable()
    SendErrorNotConnected

  fun ref close(conn: TCPConnection ref) =>
    _Unreachable()

  fun ref hard_close(conn: TCPConnection ref) =>
    _Unreachable()

  fun ref start_tls(conn: TCPConnection ref, ssl_ctx: SSLContext val,
    host: String): (None | StartTLSError)
  =>
    _Unreachable()
    StartTLSNotConnected

  fun ref read_again(conn: TCPConnection ref) =>
    _Unreachable()

  fun is_open(): Bool => false
  fun is_closed(): Bool => false

class _ClientConnecting is _ConnectionState
  var _pending_close: Bool = false

  fun ref own_event(conn: TCPConnection ref, flags: U32, arg: U32) =>
    _Unreachable()

  fun ref foreign_event(conn: TCPConnection ref, event: AsioEventID,
    flags: U32, arg: U32)
  =>
    if not AsioEvent.writeable(flags) then return end

    let fd = PonyAsio.event_fd(event)
    let remaining = conn._decrement_inflight()

    if _pending_close then
      // Straggler cleanup during close — don't establish, just clean up
      conn._straggler_cleanup(event)

      if remaining == 0 then
        // All inflight drained — fire failure and transition
        conn._set_state(_Closed)
        conn._hard_close_connecting()
      end
      return
    end

    if conn._is_socket_connected(fd) then
      conn._establish_connection(event, fd)
    else
      conn._connecting_event_failed(event, fd)
    end

  fun ref send(conn: TCPConnection ref,
    data: (ByteSeq | ByteSeqIter)): (SendToken | SendError)
  =>
    SendErrorNotConnected

  fun ref close(conn: TCPConnection ref) =>
    _pending_close = true

  fun ref hard_close(conn: TCPConnection ref) =>
    conn._set_state(_Closed)
    conn._hard_close_connecting()

  fun ref start_tls(conn: TCPConnection ref, ssl_ctx: SSLContext val,
    host: String): (None | StartTLSError)
  =>
    StartTLSNotConnected

  fun ref read_again(conn: TCPConnection ref) =>
    None

  fun is_open(): Bool => false
  fun is_closed(): Bool => false

class _Open is _ConnectionState
  fun ref own_event(conn: TCPConnection ref, flags: U32, arg: U32) =>
    if AsioEvent.writeable(flags) then
      conn._set_writeable()
      ifdef windows then
        conn._write_completed(arg)
      else
        conn._send_pending_writes()
      end
    end

    if AsioEvent.readable(flags) then
      conn._set_readable()
      ifdef windows then
        conn._read_completed(arg)
      else
        conn._read()
      end
    end

  fun ref foreign_event(conn: TCPConnection ref, event: AsioEventID,
    flags: U32, arg: U32)
  =>
    if not AsioEvent.writeable(flags) then return end

    // Happy Eyeballs straggler — clean up
    conn._decrement_inflight()
    conn._straggler_cleanup(event)

  fun ref send(conn: TCPConnection ref,
    data: (ByteSeq | ByteSeqIter)): (SendToken | SendError)
  =>
    conn._do_send(data)

  fun ref close(conn: TCPConnection ref) =>
    conn._set_state(_Closing)
    conn._initiate_shutdown()

  fun ref hard_close(conn: TCPConnection ref) =>
    conn._set_state(_Closed)
    conn._hard_close_connected()

  fun ref start_tls(conn: TCPConnection ref, ssl_ctx: SSLContext val,
    host: String): (None | StartTLSError)
  =>
    conn._do_start_tls(ssl_ctx, host)

  fun ref read_again(conn: TCPConnection ref) =>
    conn._do_read_again()

  fun is_open(): Bool => true
  fun is_closed(): Bool => false

class _Closing is _ConnectionState
  fun ref own_event(conn: TCPConnection ref, flags: U32, arg: U32) =>
    if AsioEvent.writeable(flags) then
      conn._set_writeable()
      ifdef windows then
        conn._write_completed(arg)
      else
        conn._send_pending_writes()
      end
    end

    if AsioEvent.readable(flags) then
      conn._set_readable()
      ifdef windows then
        conn._read_completed(arg)
      else
        conn._read()
      end
    end

    conn._check_shutdown_complete()

  fun ref foreign_event(conn: TCPConnection ref, event: AsioEventID,
    flags: U32, arg: U32)
  =>
    if not AsioEvent.writeable(flags) then return end

    // Happy Eyeballs straggler — clean up
    conn._decrement_inflight()
    conn._straggler_cleanup(event)

    // Inflight drained — can now send FIN
    conn._initiate_shutdown()
    conn._check_shutdown_complete()

  fun ref send(conn: TCPConnection ref,
    data: (ByteSeq | ByteSeqIter)): (SendToken | SendError)
  =>
    SendErrorNotConnected

  fun ref close(conn: TCPConnection ref) =>
    None

  fun ref hard_close(conn: TCPConnection ref) =>
    conn._set_state(_Closed)
    conn._hard_close_connected()

  fun ref start_tls(conn: TCPConnection ref, ssl_ctx: SSLContext val,
    host: String): (None | StartTLSError)
  =>
    StartTLSNotConnected

  fun ref read_again(conn: TCPConnection ref) =>
    conn._do_read_again()

  fun is_open(): Bool => false
  fun is_closed(): Bool => true

class _Closed is _ConnectionState
  fun ref own_event(conn: TCPConnection ref, flags: U32, arg: U32) =>
    None

  fun ref foreign_event(conn: TCPConnection ref, event: AsioEventID,
    flags: U32, arg: U32)
  =>
    if not AsioEvent.writeable(flags) then return end

    // Happy Eyeballs straggler — clean up
    conn._straggler_cleanup(event)

  fun ref send(conn: TCPConnection ref,
    data: (ByteSeq | ByteSeqIter)): (SendToken | SendError)
  =>
    SendErrorNotConnected

  fun ref close(conn: TCPConnection ref) =>
    None

  fun ref hard_close(conn: TCPConnection ref) =>
    None

  fun ref start_tls(conn: TCPConnection ref, ssl_ctx: SSLContext val,
    host: String): (None | StartTLSError)
  =>
    StartTLSNotConnected

  fun ref read_again(conn: TCPConnection ref) =>
    None

  fun is_open(): Bool => false
  fun is_closed(): Bool => true
