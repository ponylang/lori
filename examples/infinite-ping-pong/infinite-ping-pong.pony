use "../../lori"

// test app to drive the library

actor Main
  new create(env: Env) =>
    try
      let listen_auth = TCPListenAuth(env.root as AmbientAuth)
      let connect_auth = TCPConnectAuth(env.root as AmbientAuth)
      Listener(listen_auth, connect_auth, env.out)
    end

actor  Listener is TCPListenerActor
  var _listener: TCPListener = TCPListener.none()
  let _out: OutStream
  let _connect_auth: TCPConnectionAuth

  new create(listen_auth: TCPListenAuth,
    connect_auth: TCPConnectionAuth,
    out: OutStream)
  =>
    _connect_auth = connect_auth
    _out = out
    _listener = TCPListener(listen_auth, "127.0.0.1", "7669", this)

  fun ref listener(): TCPListener =>
    _listener

  fun ref on_accept(fd: U32): Server =>
    Server(fd, _out)

  fun ref on_closed() =>
    None

  fun ref on_listening() =>
    Client(_connect_auth, "127.0.0.1", "7669", "", _out)

  fun ref on_failure() =>
    _out.print("Unable to open listener")

actor Server is TCPConnectionActor
  var _connection: TCPConnection = TCPConnection.none()
  let _out: OutStream

  new create(fd: U32, out: OutStream) =>
    _out = out
    _connection =  TCPConnection.server(fd, this)

  fun ref connection(): TCPConnection =>
    _connection

  fun ref on_closed() =>
    None

  fun ref on_connected() =>
    None

  fun ref on_received(data: Array[U8] iso) =>
    _out.print(consume data)
    _connection.send("Pong")

actor Client is TCPConnectionActor
  var _connection: TCPConnection = TCPConnection.none()
  let _out: OutStream

  new create(auth: TCPConnectionAuth, host: String, port: String, from: String, out: OutStream) =>
    _out = out
    _connection = TCPConnection.client(auth, host, port, from, this)

  fun ref connection(): TCPConnection =>
    _connection

  fun on_closed() =>
    None

  fun ref on_connected() =>
   _connection.send("Ping")

  fun ref on_received(data: Array[U8] iso) =>
   _out.print(consume data)
   _connection.send("Ping")
