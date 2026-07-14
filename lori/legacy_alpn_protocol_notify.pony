interface LegacyALPNProtocolNotify
  """
  A `LegacyTCPConnectionNotify` that also implements this is told the ALPN
  protocol negotiated, once the handshake is complete.

  This mirrors the `ssl/net` package's `ALPNProtocolNotify`, retyped to
  `LegacyTCPConnection` (the stdlib version is typed to `net.TCPConnection`,
  which a `LegacySSLConnection` never handles).
  """
  fun ref alpn_negotiated(
    conn: LegacyTCPConnection ref,
    protocol: (String | None))
    : None
    """
    The protocol the peers agreed on, or `None` when they agreed on none.
    Called once, before any application data reaches `received`.
    """
