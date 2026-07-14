use net = "net"

actor LegacyTCPListener is TCPListenerActor
  """
  A TCP listener with the shape of the standard library `net` package's
  `TCPListener`, built on lori. Create one to accept connections:

  ```pony
  LegacyTCPListener(TCPListenAuth(env.root), MyListenNotify, "", "8989")
  ```

  For each accepted connection, the `connected` method of the
  `LegacyTCPListenNotify` you supply returns a `LegacyTCPConnectionNotify` for
  it. The listener builds the accepted connection and wires the two together.
  """
  var _tcp_listener: TCPListener = TCPListener.none()
  var _notify: LegacyTCPListenNotify
  let _server_auth: TCPServerAuth
  let _rbs: USize
  let _yield_after_reading: USize

  new create(
    auth: TCPListenAuth,
    notify: LegacyTCPListenNotify iso,
    host: String = "",
    service: String = "0",
    limit: USize = 0,
    read_buffer_size: USize = 16384,
    yield_after_reading: USize = 16384,
    yield_after_writing: USize = 16384)
  =>
    """
    Listen for both IPv4 and IPv6 connections. `limit` caps concurrent
    connections; 0 means no limit. `yield_after_writing` is accepted for source
    compatibility but has no effect (see the package documentation).
    """
    _notify = consume notify
    _server_auth = TCPServerAuth(auth)
    _rbs = read_buffer_size
    _yield_after_reading = yield_after_reading
    _tcp_listener =
      TCPListener(
        auth, host, service, this, DualStack, _LegacyMaxSpawn(limit))

  new ip4(
    auth: TCPListenAuth,
    notify: LegacyTCPListenNotify iso,
    host: String = "",
    service: String = "0",
    limit: USize = 0,
    read_buffer_size: USize = 16384,
    yield_after_reading: USize = 16384,
    yield_after_writing: USize = 16384)
  =>
    """
    Listen for IPv4 connections.
    """
    _notify = consume notify
    _server_auth = TCPServerAuth(auth)
    _rbs = read_buffer_size
    _yield_after_reading = yield_after_reading
    _tcp_listener =
      TCPListener(auth, host, service, this, IP4, _LegacyMaxSpawn(limit))

  new ip6(
    auth: TCPListenAuth,
    notify: LegacyTCPListenNotify iso,
    host: String = "",
    service: String = "0",
    limit: USize = 0,
    read_buffer_size: USize = 16384,
    yield_after_reading: USize = 16384,
    yield_after_writing: USize = 16384)
  =>
    """
    Listen for IPv6 connections.
    """
    _notify = consume notify
    _server_auth = TCPServerAuth(auth)
    _rbs = read_buffer_size
    _yield_after_reading = yield_after_reading
    _tcp_listener =
      TCPListener(auth, host, service, this, IP6, _LegacyMaxSpawn(limit))

  fun ref _listener(): TCPListener =>
    _tcp_listener

  be set_notify(notify: LegacyTCPListenNotify iso) =>
    """
    Replace the notifier.
    """
    _notify = consume notify

  fun ref local_address(): net.NetAddress =>
    """
    The bound local IP address.
    """
    _tcp_listener.local_address()

  fun ref _on_accept(fd: U32): TCPConnectionActor ? =>
    _LegacyServerConnection._accept(
      _server_auth, _notify.connected(this)?, fd, _rbs, _yield_after_reading)

  fun ref _on_listening() =>
    _notify.listening(this)

  fun ref _on_listen_failure() =>
    _notify.not_listening(this)

  fun ref _on_closed() =>
    _notify.closed(this)
