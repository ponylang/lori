"""
Socket option tuning on a connected TCP connection.

A self-contained echo server that configures TCP_NODELAY and OS buffer sizes on
each accepted connection. The client connects, sends "Hello", receives the echo,
and prints the configured socket option values before closing. Demonstrates
`set_nodelay()`, `set_so_rcvbuf()`, `get_so_rcvbuf()`, `set_so_sndbuf()`, and
`get_so_sndbuf()` on a live connection.
"""
use "../../lori"

actor Main
  new create(env: Env) =>
    let listen_auth = TCPListenAuth(env.root)
    let connect_auth = TCPConnectAuth(env.root)
    SocketOptionsListener(listen_auth, connect_auth, "127.0.0.1", "7676",
      env.out)

actor SocketOptionsListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _out: OutStream
  let _connect_auth: TCPConnectAuth
  let _server_auth: TCPServerAuth

  new create(listen_auth: TCPListenAuth, connect_auth: TCPConnectAuth,
    host: String, port: String, out: OutStream)
  =>
    _out = out
    _connect_auth = connect_auth
    _server_auth = TCPServerAuth(listen_auth)
    _tcp_listener = TCPListener(listen_auth, host, port, this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): SocketOptionsServer =>
    SocketOptionsServer(_server_auth, fd, _out)

  fun ref _on_listening() =>
    _out.print("Listener started on 127.0.0.1:7676")
    SocketOptionsClient(_connect_auth, "127.0.0.1", "7676", _out)

  fun ref _on_listen_failure() =>
    _out.print("Couldn't start listener.")

  fun ref _on_closed() =>
    _out.print("Listener closed.")

actor SocketOptionsServer is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _out: OutStream

  new create(auth: TCPServerAuth, fd: U32, out: OutStream) =>
    _out = out
    _tcp_connection = TCPConnection.server(auth, fd, this, this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_started() =>
    // Disable Nagle for low-latency responses
    _tcp_connection.set_nodelay(true)

    // Set OS buffer sizes
    _tcp_connection.set_so_rcvbuf(32768)
    _tcp_connection.set_so_sndbuf(32768)

    // Read back the actual values (OS may round up)
    (let rcv_errno: U32, let rcv_size: U32) =
      _tcp_connection.get_so_rcvbuf()
    (let snd_errno: U32, let snd_size: U32) =
      _tcp_connection.get_so_sndbuf()

    if (rcv_errno == 0) and (snd_errno == 0) then
      _out.print("Server: rcvbuf=" + rcv_size.string()
        + " sndbuf=" + snd_size.string())
    else
      _out.print("Server: failed to read buffer sizes")
    end

  fun ref _on_received(data: Array[U8] iso) =>
    _tcp_connection.send(consume data)

  fun ref _on_closed() =>
    _out.print("Server: connection closed")

actor SocketOptionsClient is
  (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _out: OutStream

  new create(auth: TCPConnectAuth, host: String, port: String,
    out: OutStream)
  =>
    _out = out
    _tcp_connection = TCPConnection.client(auth, host, port, "", this, this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _tcp_connection.send("Hello")

  fun ref _on_received(data: Array[U8] iso) =>
    _out.print("Client: received echo: " + String.from_array(consume data))
    _tcp_connection.close()

  fun ref _on_closed() =>
    _out.print("Client: closed")
