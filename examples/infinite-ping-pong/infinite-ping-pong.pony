use "../../lori"

// test app to drive the library

actor Main
  new create(env: Env) =>
    Listener(env.out)

actor Listener is TCPListenerActor
  let state: TCPListener
  let _out: OutStream

  new create(out: OutStream) =>
    _out = out
    state = TCPListener("127.0.0.1", "7669")
    open()

  fun ref self(): TCPListener =>
    state

  fun ref on_accept(fd: U32): Server =>
    Server(fd, _out)

  fun ref on_closed() =>
    None

  fun ref on_listening() =>
    Client("127.0.0.1", "7669", "", _out)

  fun ref on_failure() =>
    _out.print("Unable to open listener")

actor Server is TCPConnectionActor
  var _state: TCPConnection = TCPConnection.none()
  let _out: OutStream

  new create(fd: U32, out: OutStream) =>
    _out = out
    _state =  TCPConnection.server(fd, this)

  fun ref self(): TCPConnection =>
    _state

  fun ref on_closed() =>
    None

  fun ref on_connected() =>
    None

  fun ref on_received(data: Array[U8] iso) =>
    _out.print(consume data)
    _state.send(this, "Pong")

actor Client is TCPConnectionActor
  var _state: TCPConnection = TCPConnection.none()
  let _out: OutStream

  new create(host: String, port: String, from: String, out: OutStream) =>
    _out = out
    _state = TCPConnection.client(host, port, from, this)

  fun ref self(): TCPConnection =>
    _state

  fun on_closed() =>
    None

  fun ref on_connected() =>
   _state.send(this, "Ping")

  fun ref on_received(data: Array[U8] iso) =>
   _out.print(consume data)
   _state.send(this, "Ping")
