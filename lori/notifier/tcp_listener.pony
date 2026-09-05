use lori = ".."
use "ssl/net"

actor TCPListener is lori.TCPListenerActor
  """
  A TCP listener actor driven by a
  [`TCPListenNotify`](/lori/notifier-TCPListenNotify/).

  Wraps lori's `TCPListener` class and `TCPListenerActor` trait into a single
  actor. When a client connects, the listener asks the notifier for a
  `ServerTCPConnectionNotify` and creates a `ServerTCPConnection` internally.
  """
  var _tcp_listener: lori.TCPListener = lori.TCPListener.none()
  var _notify: TCPListenNotify ref
  let _server_auth: lori.TCPServerAuth
  let _ssl_ctx: (SSLContext val | None)

  new create(auth: lori.TCPListenAuth,
    notify: TCPListenNotify iso,
    host: String,
    service: String,
    limit: (lori.MaxSpawn | None) = lori.DefaultMaxSpawn(),
    ip_version: lori.IPVersion = lori.DualStack)
  =>
    """
    Open a plaintext TCP listener on `host`:`service`.
    """
    _notify = consume notify
    _server_auth = lori.TCPServerAuth(auth)
    _ssl_ctx = None
    _tcp_listener =
      lori.TCPListener(
        auth, host, service, this, ip_version, limit)

  new ssl(auth: lori.TCPListenAuth,
    notify: TCPListenNotify iso,
    ctx: SSLContext val,
    host: String,
    service: String,
    limit: (lori.MaxSpawn | None) = lori.DefaultMaxSpawn(),
    ip_version: lori.IPVersion = lori.DualStack)
  =>
    """
    Open an SSL TCP listener on `host`:`service`. Accepted connections use
    `ctx` for the TLS handshake.
    """
    _notify = consume notify
    _server_auth = lori.TCPServerAuth(auth)
    _ssl_ctx = ctx
    _tcp_listener =
      lori.TCPListener(
        auth, host, service, this, ip_version, limit)

  // --- TCPListenerActor ------------------------------------------------------
  fun ref _listener(): lori.TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): ServerTCPConnection ? =>
    let notify = _notify.on_connected(this)?
    match _ssl_ctx
    | let ctx: SSLContext val =>
      ServerTCPConnection._ssl_create(_server_auth, ctx, fd, consume notify)
    else
      ServerTCPConnection._create(_server_auth, fd, consume notify)
    end

  fun ref _on_listening() =>
    _notify.on_listening(this)

  fun ref _on_listen_failure() =>
    _notify.on_not_listening(this)

  fun ref _on_closed() =>
    _notify.on_closed(this)

  // --- Synchronous methods ---------------------------------------------------
  fun ref local_address(): lori.NetAddress =>
    """
    Return the local IP address the listener is bound to.
    """
    _tcp_listener.local_address()

  fun ref close() =>
    """
    Close the listener. No further connections are accepted. `on_closed` fires
    on the notifier.
    """
    _tcp_listener.close()
