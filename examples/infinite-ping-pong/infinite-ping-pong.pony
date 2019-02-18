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
  let _connect_auth: OutgoingTCPAuth
  let _server_auth: TCPServerAuth

  new create(listen_auth: TCPListenAuth,
    connect_auth: OutgoingTCPAuth,
    out: OutStream)
  =>
    _connect_auth = connect_auth
    _out = out
    _server_auth = TCPServerAuth(listen_auth)
    _listener = TCPListener(listen_auth, "127.0.0.1", "7669", this)

  fun ref listener(): TCPListener =>
    _listener

  fun ref on_accept(fd: U32): Server =>
    Server(_server_auth, fd, _out)

  fun ref on_listening() =>
    Client(_connect_auth, "127.0.0.1", "7669", "", _out)

  fun ref on_failure() =>
    _out.print("Unable to open listener")

actor Server is TCPServerActor
  var _connection: TCPConnection = TCPConnection.none()
  let _out: OutStream

  new create(auth: IncomingTCPAuth, fd: U32, out: OutStream) =>
    _out = out
    _connection =  TCPConnection.server(auth, fd, this)

  fun ref connection(): TCPConnection =>
    _connection

  fun ref on_received(data: Array[U8] iso) =>
    _out.print(consume data)
    _connection.send("Pong")

actor Client is TCPClientActor
  var _connection: TCPConnection = TCPConnection.none()
  let _out: OutStream

  new create(auth: OutgoingTCPAuth,
    host: String,
    port: String,
    from: String,
    out: OutStream)
  =>
    _out = out
    _connection = TCPConnection.client(auth, host, port, from, this)

  fun ref connection(): TCPConnection =>
    _connection

  fun ref on_connected() =>
   _connection.send("Ping")

  fun ref on_received(data: Array[U8] iso) =>
   _out.print(consume data)
   _connection.send("Ping")
