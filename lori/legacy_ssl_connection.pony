use "collections"
use "ssl/net"

class LegacySSLConnection is LegacyTCPConnectionNotify
  """
  Wrap another protocol in an SSL connection.

  This mirrors the standard library `ssl/net` package's `SSLConnection`
  decorator, retyped to `LegacyTCPConnectionNotify`. It wraps a plaintext
  `LegacyTCPConnection` (created with `LegacyTCPClient` or accepted by
  `LegacyTCPListener`) and a wrapped notifier, running the TLS handshake and
  record framing on top. Give the wrapped notifier's `connected`/`accepted` and
  `received` the decrypted view; the ciphertext goes to the connection via
  `write_final`, which does not re-run `sent`.

  This is independent of lori's built-in SSL (the `ssl_client`/`ssl_server`
  `TCPConnection` constructors); it reproduces the old decorator API for code
  moving from `ssl/net`.
  """
  let _notify: LegacyTCPConnectionNotify
  let _ssl: SSL
  var _connected: Bool = false
  var _expect: USize = 0
  var _closed: Bool = false
  let _pending: List[ByteSeq] = _pending.create()
  var _accept_pending: Bool = false

  new iso create(notify: LegacyTCPConnectionNotify iso, ssl: SSL iso) =>
    """
    Initialise with a wrapped protocol and an SSL session.
    """
    _notify = consume notify
    _ssl = consume ssl

  fun ref accepted(conn: LegacyTCPConnection ref) =>
    """
    Swallow this event until the handshake is complete.
    """
    _accept_pending = true
    _poll(conn)

  fun ref connecting(conn: LegacyTCPConnection ref, count: U32) =>
    """
    Forward to the wrapped protocol.
    """
    _notify.connecting(conn, count)

  fun ref connected(conn: LegacyTCPConnection ref) =>
    """
    Swallow this event until the handshake is complete.
    """
    _poll(conn)

  fun ref connect_failed(conn: LegacyTCPConnection ref) =>
    """
    Forward to the wrapped protocol.
    """
    _notify.connect_failed(conn)

  fun ref sent(conn: LegacyTCPConnection ref, data: ByteSeq): ByteSeq =>
    """
    Pass the data to the SSL session and check for both new application data
    and new destination data.
    """
    let notified = _notify.sent(conn, data)
    if _connected then
      try
        _ssl.write(notified)?
      else
        return ""
      end
    else
      _pending.push(notified)
    end

    _poll(conn)
    ""

  fun ref sentv(conn: LegacyTCPConnection ref, data: ByteSeqIter): ByteSeqIter
  =>
    """
    Pass each sequence to the SSL session and check for both new application
    data and new destination data. Returns an empty sequence: what leaves the
    connection is the ciphertext `_poll` writes, not these bytes.
    """
    let ret = recover val Array[ByteSeq] end
    let data' = _notify.sentv(conn, data)
    for bytes in data'.values() do
      if _connected then
        try
          _ssl.write(bytes)?
        else
          return ret
        end
      else
        _pending.push(bytes)
      end
    end

    _poll(conn)
    ret

  fun ref received(
    conn: LegacyTCPConnection ref,
    data: Array[U8] iso,
    times: USize)
    : Bool
  =>
    """
    Pass the data to the SSL session and check for both new application data
    and new destination data.
    """
    _ssl.receive(consume data)
    _poll(conn)

  fun ref expect(conn: LegacyTCPConnection ref, qty: USize): USize =>
    """
    Keep track of the expect count for the wrapped protocol. Always tell the
    connection to read all available data.
    """
    _expect = _notify.expect(conn, qty)
    0

  fun ref closed(conn: LegacyTCPConnection ref) =>
    """
    Forward to the wrapped protocol.
    """
    _closed = true

    _poll(conn)
    _ssl.dispose()

    _connected = false
    _pending.clear()
    _notify.closed(conn)

  fun ref throttled(conn: LegacyTCPConnection ref) =>
    """
    Forward to the wrapped protocol.
    """
    _notify.throttled(conn)

  fun ref unthrottled(conn: LegacyTCPConnection ref) =>
    """
    Forward to the wrapped protocol.
    """
    _notify.unthrottled(conn)

  fun ref _poll(conn: LegacyTCPConnection ref): Bool =>
    """
    Check for both new application data and new destination data. Inform the
    wrapped protocol that it has connected when the handshake is complete.
    """
    match _ssl.state()
    | SSLReady =>
      if not _connected then
        _connected = true
        if _accept_pending then
          _notify.accepted(conn)
        else
          _notify.connected(conn)
        end

        match _notify
        | let alpn_notify: LegacyALPNProtocolNotify =>
          alpn_notify.alpn_negotiated(conn, _ssl.alpn_selected())
        end

        try
          while true do
            let bytes = try _pending.shift()? else break end
            _ssl.write(bytes)?
          end
        end
      end
    | SSLAuthFail =>
      _notify.auth_failed(conn)

      if not _closed then
        conn.close()
      end

      return true
    | SSLError =>
      if not _closed then
        conn.close()
      end

      return true
    | SSLDisposed =>
      // `closed` disposes the session after its last `_poll`, so this arm is
      // not reached while the connection is open. Once the session is gone
      // there is nothing to read and nothing to send.
      return false
    end

    var continue_reading: Bool = true

    try
      var received_called: USize = 0

      while true do
        let r = _ssl.read(_expect)

        if r isnt None then
          received_called = received_called + 1
          if not _notify.received(
            conn,
            (consume r) as Array[U8] iso^,
            received_called)
          then
            continue_reading = false
            break
          end
        else
          break
        end
      end
    end

    try
      while _ssl.can_send() do
        conn.write_final(_ssl.send()?)
      end
    end

    continue_reading
