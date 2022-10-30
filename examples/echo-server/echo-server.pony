use "../../lori"

actor Main
  new create(env: Env) =>
    let auth = TCPListenAuth(env.root)
    let echo = EchoServer(auth, "", "7669", env.out)

actor EchoServer is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _out: OutStream
  let _server_auth: TCPServerAuth

  new create(listen_auth: TCPListenAuth,
    host: String,
    port: String,
    out: OutStream)
  =>
    _out = out
    _server_auth = TCPServerAuth(listen_auth)
    _tcp_listener = TCPListener(listen_auth, host, port, this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): TCPServerActor =>
    Echoer(_server_auth, fd, _out)

  fun ref _on_closed() =>
    _out.print("Echo server shut down.")

  fun ref _on_listen_failure() =>
    _out.print("Couldn't start Echo server. " +
      "Perhaps try another network interface?")

  fun ref _on_listening() =>
    _out.print("Echo server started.")

actor Echoer is TCPServerActor
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _out: OutStream

  new create(auth: TCPServerAuth, fd: U32, out: OutStream) =>
    _out = out
    _tcp_connection = TCPConnection.server(auth, fd, this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_closed() =>
    _out.print("Connection Closed")

  fun ref _on_received(data: Array[U8] iso) =>
    _out.print("Data received. Echoing it back.")
    _tcp_connection.send(consume data)
