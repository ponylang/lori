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

  fun ref on_accept(state': TCPConnection iso): Server =>
    Server(consume state', _out)

  fun ref on_closed() =>
    None

  fun ref on_listening() =>
    Client("127.0.0.1", "7669", "", _out)

  fun ref on_failure() =>
    _out.print("Unable to open listener")

actor Server is TCPConnectionActor
  let state: TCPConnection
  let _out: OutStream

  new create(state': TCPConnection iso, out: OutStream) =>
    state = consume state'
    _out = out

  fun ref self(): TCPConnection =>
    state

  fun ref on_closed() =>
    None

  fun ref on_connected() =>
    None

  fun ref on_received(data: Array[U8] iso) =>
    _out.print(consume data)
    state.send(this, "Pong")

actor Client is TCPConnectionActor
  let state: TCPConnection
  let _out: OutStream

  new create(host: String, port: String, from: String, out: OutStream) =>
    _out = out
    state = TCPConnection.client()
    connect(host, port, from)

  fun ref self(): TCPConnection =>
    state

  fun on_closed() =>
    None

  fun ref on_connected() =>
   state.send(this, "Ping")

  fun ref on_received(data: Array[U8] iso) =>
   _out.print(consume data)
   state.send(this, "Ping")
