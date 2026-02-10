## Add TLS upgrade support (STARTTLS)

Lori now supports upgrading an established plaintext TCP connection to TLS mid-stream via `start_tls()`. This enables protocols like PostgreSQL, SMTP, and LDAP that negotiate TLS after an initial plaintext exchange.

```pony
actor MyClient is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _sslctx: SSLContext val

  new create(auth: TCPConnectAuth, sslctx: SSLContext val,
    host: String, port: String)
  =>
    _sslctx = sslctx
    _tcp_connection = TCPConnection.client(auth, host, port, "", this, this)

  fun ref _connection(): TCPConnection => _tcp_connection

  fun ref _on_connected() =>
    // Negotiate upgrade over plaintext
    _tcp_connection.send("STARTTLS")

  fun ref _on_received(data: Array[U8] iso) =>
    if String.from_array(consume data) == "OK" then
      // Server agreed — initiate TLS handshake
      _tcp_connection.start_tls(_sslctx, "localhost")
    end

  fun ref _on_tls_ready() =>
    // Handshake complete — connection is now encrypted
    _tcp_connection.send("encrypted payload")

  fun ref _on_tls_failure() =>
    // Handshake failed — _on_closed will follow
    None
```

`start_tls()` returns `None` when the handshake has been started, or a `StartTLSError` if the upgrade cannot proceed (connection not open, already TLS, muted, buffered read data, or pending writes). During the handshake, `send()` returns `SendErrorNotConnected`. When the handshake completes, `_on_tls_ready()` fires. If it fails, `_on_tls_failure()` fires followed by `_on_closed()`.
