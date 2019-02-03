use "lori"

// test app to drive the library

actor Main
  new create(env: Env) =>
    Listener(env.out) 
    Client("127.0.0.1", "7669", "", env.out)

actor Listener is TCPListenerActor
  let state: TCPListener
  let _out: OutStream

  new create(out: OutStream) =>
    _out = out
    state = TCPListener("127.0.0.1", "7669")
    open()

  fun ref self(): TCPListener =>
    state

  fun on_accept(state': TCPConnection iso): Server =>
    Server(consume state', _out)
  
actor Server is TCPConnectionActor
  let state: TCPConnection
  let _out: OutStream

  new create(state': TCPConnection iso, out: OutStream) =>
    state = consume state'
    _out = out

  fun ref self(): TCPConnection =>
    state 

  fun ref on_connected() =>
    @printf[I32]("Server connected\n".cstring())

  fun ref on_received(data: Array[U8] iso) =>
    @printf[I32]("server recv\n".cstring())
    _out.print(consume data)
    send("Pong")

actor Client is TCPConnectionActor
  let state: TCPConnection
  let _out: OutStream

  new create(host: String, port: String, from: String, out: OutStream) =>
    _out = out
    state = TCPConnection.client()
    connect(host, port, from)

  fun ref self(): TCPConnection =>
    state

  fun ref on_connected() =>
    send("Ping")

  fun ref on_received(data: Array[U8] iso) =>
   @printf[I32]("client recv\n".cstring())
   _out.print(consume data)
   send("Ping")
