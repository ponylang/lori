use "lori"

// test app to drive the library

actor Main
  new create(env: Env) =>
    Listener 

actor Listener is TCPListenerActor
  let state: TCPListener

  new create() =>
    state = TCPListener("127.0.0.1", "7669")
    open()

  fun ref self(): TCPListener =>
    state

  fun on_accept(state': TCPConnection iso): Server =>
    Server(consume state')
  
actor Server is TCPConnectionActor
  let state: TCPConnection

  new create(state': TCPConnection iso) =>
    state = consume state'

  fun ref self(): TCPConnection =>
    state 

  fun ref on_connected() =>
    send("Hi There! You are now connected!\n")

  fun ref on_received(data: Array[U8] iso) =>
    send("You sent: ")
    send(consume data)
