use "../../lori"

actor Main
  new create(env: Env) =>
    try
      let auth = TCPListenAuth(env.root as AmbientAuth)
      let echo = EchoServer(auth, "", "7669", env.out)
    end

actor EchoServer is TCPListenerActor
  var _listener: TCPListener = TCPListener.none()
  let _out: OutStream
  let _server_auth: TCPServerAuth

  new create(listen_auth: TCPListenAuth,
    host: String,
    port: String,
    out: OutStream)
  =>
    _out = out
    _server_auth = TCPServerAuth(listen_auth)
    _listener = TCPListener(listen_auth, host, port, this)

  fun ref listener(): TCPListener =>
    _listener

  fun ref on_accept(fd: U32): TCPConnectionActor =>
    Echoer(_server_auth, fd, _out)

  fun ref on_closed() =>
    _out.print("Echo server shut down.")

  fun ref on_failure() =>
    _out.print("Couldn't start Echo server. " +
      "Perhaps try another network interface?")

  fun ref on_listening() =>
    _out.print("Echo server started.")

actor Echoer is TCPConnectionActor
  var _connection: TCPConnection = TCPConnection.none()
  let _out: OutStream

  new create(auth: TCPConnectionServerAuth, fd: U32, out: OutStream) =>
    _out = out
    _connection = TCPConnection.server(auth, fd, this)

  fun ref connection(): TCPConnection =>
    _connection

  fun ref on_closed() =>
    _out.print("Connection Closed")

  fun ref on_connected() =>
    _out.print("We have a new connection!")

  fun ref on_received(data: Array[U8] iso) =>
    _out.print("Data received. Echoing it back.")
    _connection.send(consume data)
