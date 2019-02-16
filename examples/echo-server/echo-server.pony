use "../../lori"

actor Main
  new create(env: Env) =>
    let echo = EchoServer("", "7669", env.out)

actor EchoServer is TCPListenerActor
  var _listener: TCPListener = TCPListener.none()
  let _out: OutStream

  new create(host: String, port: String, out: OutStream) =>
    _out = out
    _listener = TCPListener(host, port, this)

  fun ref listener(): TCPListener =>
    _listener

  fun ref on_accept(fd: U32): TCPConnectionActor =>
    Echoer(fd, _out)

  fun ref on_closed() =>
    _out.print("Echo server shut down.")

  fun ref on_failure() =>
    _out.print("Couldn't start Echo server. Perhaps try another network interface?")

  fun ref on_listening() =>
    _out.print("Echo server started.")

actor Echoer is TCPConnectionActor
  var _connection: TCPConnection = TCPConnection.none()
  let _out: OutStream

  new create(fd: U32, out: OutStream) =>
    _out = out
    _connection = TCPConnection.server(fd, this)

  fun ref connection(): TCPConnection =>
    _connection

  fun ref on_closed() =>
    _out.print("Connection Closed")

  fun ref on_connected() =>
    _out.print("We have a new connection!")

  fun ref on_received(data: Array[U8] iso) =>
    _out.print("Data received. Echoing it back.")
    _connection.send(consume data)
