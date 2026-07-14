interface LegacyTCPConnectionNotify
  """
  Notifications for a `LegacyTCPConnection`.

  This mirrors the standard library `net` package's `TCPConnectionNotify`
  interface so that code written against the old API can move to lori with
  small changes. The one required change is the `conn` parameter type: it is
  `LegacyTCPConnection ref` here, where the stdlib used `TCPConnection ref`.

  For an example of use, see the documentation for `LegacyTCPConnection` and
  `LegacyTCPListener`.
  """
  fun ref accepted(conn: LegacyTCPConnection ref) =>
    """
    Called when a connection is accepted by a `LegacyTCPListener`.
    """
    None

  fun ref proxy_via(host: String, service: String): (String, String) =>
    """
    Called before attempting to connect to the destination server. To connect
    via a proxy, return the host and service of the proxy server. The default
    returns the destination unchanged, so no proxy is used.
    """
    (host, service)

  fun ref connecting(conn: LegacyTCPConnection ref, count: U32) =>
    """
    Called if name resolution succeeded and connection attempts are now in
    progress. `count` is the number of attempts being tried. Called each time
    the count changes, until a connection is made or `connect_failed` is
    called.
    """
    None

  fun ref connected(conn: LegacyTCPConnection ref) =>
    """
    Called when a connection to the server has succeeded.
    """
    None

  fun ref connect_failed(conn: LegacyTCPConnection ref)
    """
    Called when every connection attempt has failed. The connection will never
    be established.

    You must implement error handling. To ignore the failure, provide an empty
    body:

    ```pony
    fun ref connect_failed(conn: LegacyTCPConnection ref) =>
      None
    ```
    """

  fun ref auth_failed(conn: LegacyTCPConnection ref) =>
    """
    A plaintext connection has no authentication mechanism. When a protocol is
    wrapped in another (e.g. SSL via `LegacySSLConnection`), this reports an
    authentication failure in the lower-level protocol.
    """
    None

  fun ref sent(conn: LegacyTCPConnection ref, data: ByteSeq): ByteSeq =>
    """
    Called when data is sent on the connection via `write`. Return the data to
    write, or an empty sequence to swallow the send. This is the hook a
    protocol wrapper (e.g. `LegacySSLConnection`) uses to transform outgoing
    data.
    """
    data

  fun ref sentv(conn: LegacyTCPConnection ref, data: ByteSeqIter): ByteSeqIter
  =>
    """
    Called when several chunks of data are sent in one `writev`. Return the
    chunks to write, or an empty sequence to swallow the send.
    """
    data

  fun ref received(
    conn: LegacyTCPConnection ref,
    data: Array[U8] iso,
    times: USize)
    : Bool
  =>
    """
    Called when new data arrives on the connection. Return `true` to keep
    reading, or `false` to yield to other actors now.

    `times` is the number of times `received` has been called since the last
    yield. It lets the notifier end a run of reads on a regular basis.
    """
    true

  fun ref expect(conn: LegacyTCPConnection ref, qty: USize): USize =>
    """
    Called when the connection has been told to expect `qty` bytes. A wrapping
    notifier can change the expected quantity, letting a lower-level protocol
    handle framing (e.g. SSL).
    """
    qty

  fun ref closed(conn: LegacyTCPConnection ref) =>
    """
    Called when the connection is closed.
    """
    None

  fun ref throttled(conn: LegacyTCPConnection ref) =>
    """
    Called when the connection starts experiencing backpressure. Pause calls to
    `write` and `writev` until `unthrottled` is called. Unlike the standard
    library, lori does not queue writes made while throttled — they are dropped.
    """
    None

  fun ref unthrottled(conn: LegacyTCPConnection ref) =>
    """
    Called when backpressure is released. You may resume calling `write` and
    `writev`.
    """
    None
