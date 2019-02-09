use "../../lori"

actor Main
  new create(env: Env) =>
    let echo = EchoServer("", "7669", env.out)
    echo.start()

actor EchoServer is TCPListenerActor 
  let _state: TCPListener
  let _out: OutStream

  new create(host: String, port: String, out: OutStream) =>
    _state = TCPListener(host, port) 
    _out = out

  be start() =>
    open()

  fun ref self(): TCPListener =>
    _state

  fun ref on_accept(state: TCPConnection iso): TCPConnectionActor =>
    Echoer(consume state, _out)

  fun ref on_closed() =>
    _out.print("Echo server shut down.")

  fun ref on_failure() =>
    _out.print("Couldn't start Echo server. Perhaps try another network interface?")

  fun ref on_listening() =>
    _out.print("Echo server started.")

actor Echoer is TCPConnectionActor
  let _state: TCPConnection
  let _out: OutStream

  new create(state: TCPConnection iso, out: OutStream) =>
    _state = consume state
    _out = out

  fun ref self(): TCPConnection =>
    _state

  fun ref on_closed() =>
    _out.print("Connection Closed")

  fun ref on_connected() =>
    _out.print("We have a new connection!")

  fun ref on_received(data: Array[U8] iso) =>
    _out.print("Data received. Echoing it back.")
    send(consume data)
