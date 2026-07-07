"""
Demonstrates per-send completion tracking.

Every send() that returns a SendToken gets exactly one terminal callback:
_on_sent(token) once its bytes reach the OS, or _on_send_failed(token) if the
connection closes first. The token identifies WHICH send completed, so an
application can track exactly which of several outstanding sends have been
handed to the OS -- not just how many.

This client sends five labeled messages up front and keeps a map of the ones
still outstanding, keyed by token id. As each _on_sent arrives it reports which
message completed and drops it from the map; when the map is empty every send
has reached the OS and the client closes. If the connection had dropped with
sends still outstanding, _on_send_failed would report which ones did not make
it -- the same map, read the other way.

"Reached the OS" means written to the kernel send buffer, not received by the
peer. End-to-end delivery is still the application's job.
"""
use "../../lori"
use "collections"

actor Main
  new create(env: Env) =>
    Listener(TCPListenAuth(env.root), TCPConnectAuth(env.root), env.out)

actor Listener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _out: OutStream
  let _connect_auth: TCPConnectAuth
  let _server_auth: TCPServerAuth

  new create(listen_auth: TCPListenAuth, connect_auth: TCPConnectAuth,
    out: OutStream)
  =>
    _connect_auth = connect_auth
    _out = out
    _server_auth = TCPServerAuth(listen_auth)
    _tcp_listener = TCPListener(listen_auth, "127.0.0.1", "7688", this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): Sink =>
    Sink(_server_auth, fd, _out)

  fun ref _on_listening() =>
    _out.print("Listener ready, launching client...")
    Sender(_connect_auth, "127.0.0.1", "7688", _out)

  fun ref _on_listen_failure() =>
    _out.print("Unable to open listener")

actor Sink is (TCPConnectionActor & ServerLifecycleEventReceiver)
  """
  Server-side connection that receives and discards data.
  """
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _out: OutStream

  new create(auth: TCPServerAuth, fd: U32, out: OutStream) =>
    _out = out
    _tcp_connection = TCPConnection.server(auth, fd, this, this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_received(data: Array[U8] iso) =>
    None

  fun ref _on_closed() =>
    _out.print("Sink: connection closed")

actor Sender is (TCPConnectionActor & ClientLifecycleEventReceiver)
  """
  Sends several labeled messages and tracks which ones have reached the OS by
  their SendToken.
  """
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _out: OutStream
  let _messages: Array[String] val
  // Sends still waiting for _on_sent, keyed by token id.
  let _outstanding: Map[USize, String] = _outstanding.create()

  new create(auth: TCPConnectAuth, host: String, port: String,
    out: OutStream)
  =>
    _out = out
    _messages = recover val
      ["login"; "subscribe"; "query"; "heartbeat"; "logout"]
    end
    _tcp_connection = TCPConnection.client(auth, host, port, "", this, this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _out.print("Sender: connected, sending " + _messages.size().string()
      + " messages")
    for msg in _messages.values() do
      match _tcp_connection.send(msg)
      | let token: SendToken =>
        _outstanding(token.id) = msg
        _out.print("  sent '" + msg + "' (token " + token.id.string()
          + "), awaiting _on_sent")
      | let _: SendError =>
        _out.print("  could not send '" + msg + "'")
      end
    end

  fun ref _on_sent(token: SendToken) =>
    try
      (_, let msg) = _outstanding.remove(token.id)?
      _out.print("_on_sent: '" + msg + "' (token " + token.id.string()
        + ") reached the OS; " + _outstanding.size().string()
        + " still outstanding")
    end
    if _outstanding.size() == 0 then
      _out.print("Sender: every send reached the OS, closing")
      _tcp_connection.close()
    end

  fun ref _on_send_failed(token: SendToken) =>
    try
      (_, let msg) = _outstanding.remove(token.id)?
      _out.print("_on_send_failed: '" + msg + "' (token " + token.id.string()
        + ") did not reach the OS before the connection closed")
    end

  fun ref _on_connection_failure(reason: ConnectionFailureReason) =>
    _out.print("Sender: connection failed")

  fun ref _on_closed() =>
    _out.print("Sender: closed")
