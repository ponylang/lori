use "collections"
use "runtime_info"
use "../../lori"
use @exit[None](status: U8)
use @fprintf[I32](stream: Pointer[U8] tag, fmt: Pointer[U8] tag, ...)
use @pony_os_stderr[Pointer[U8]]()

actor Main
  new create(env: Env) =>
    // Setting this to 127.0.0.1 instead of localhost triggers weird MacOS
    // behavior that results in us not being able to open client connections
    // after a while (somewhere around 16k).
    // See https://web.archive.org/web/20180129235834/http://danielmendel.github.io/blog/2013/04/07/benchmarkers-beware-the-ephemeral-port-limit/
    // Even with this change (that will probably help on a local machine), you
    // should seriously consider making the changes that we do in CI to run
    // this on macOS. See macOS-configure-networking.bash.
    let host = "localhost"
    let port = "7669"
    let max_concurrent_connections =
      Scheduler.schedulers(SchedulerInfoAuth(env.root))
    let total_clients_to_spawn = try
      env.args(1)?.usize()?
    else
      100_000_000
    end

    env.out.print("Will spawn a total of "
      + total_clients_to_spawn.string()
      + " clients.")

    let spawner = ClientSpawner(max_concurrent_connections,
      total_clients_to_spawn,
      TCPConnectAuth(env.root),
      host,
      port,
      env.out)

    Listener(TCPListenAuth(env.root),
      host,
      port,
      env.out,
      max_concurrent_connections,
      spawner)

  fun @runtime_override_defaults(rto: RuntimeOptions) =>
     rto.ponynoblock = true

actor Listener is TCPListenerActor
  let _max_concurrent_connections: U32
  let _auth: TCPListenAuth
  let _out: OutStream
  let _spawner: ClientSpawner
  var _tcp_listener: TCPListener = TCPListener.none()

  new create(listen_auth: TCPListenAuth,
    host: String,
    port: String,
    out: OutStream,
    max_concurrent_connections: U32,
    spawner: ClientSpawner)
  =>
    _out = out
    _auth = listen_auth
    _max_concurrent_connections = max_concurrent_connections
    _spawner = spawner
    _tcp_listener = TCPListener(
      _auth,
      host,
      port,
      this,
      _max_concurrent_connections)

  be spawner_done() =>
    _tcp_listener.close()

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): Server =>
    Server(TCPServerAuth(_auth), fd, _out)

  fun ref _on_closed() =>
    _out.print("Listener shut down.")

  fun ref _on_listen_failure() =>
    _out.print("Couldn't start listener.")

  fun ref _on_listening() =>
    _out.print("Listener started.")
    _spawner.start(this)

actor Server is (TCPConnectionActor & ServerLifecycleEventReceiver)
  """
  Sends back any data it receives.
  """
  let _out: OutStream
  var _tcp_connection: TCPConnection = TCPConnection.none()

  new create(auth: TCPServerAuth, fd: U32, out: OutStream) =>
    _out = out
    _tcp_connection = TCPConnection.server(auth, fd, this, this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _next_lifecycle_event_receiver(): (ServerLifecycleEventReceiver | None) =>
    None

  fun ref on_received(data: Array[U8] iso) =>
    //_out.print("Server received data.")
    _tcp_connection.send(consume data)

actor ClientSpawner
  let _max_concurrent_clients: U32
  let _total_clients_to_spawn: USize
  let _auth: TCPConnectAuth
  let _host: String
  let _port: String
  let _out: OutStream
  var _clients_spawned: SetIs[Client] = SetIs[Client].create()
  var _total_clients_spawned: USize = 0
  var _listener: (Listener | None) = None
  var _started: Bool = false
  var _failed: USize = 0
  var _finished: Bool = false

  new create(max_concurrent_clients: U32,
    total_clients_to_spawn: USize,
    auth: TCPConnectAuth,
    host: String,
    port: String,
    out: OutStream)
  =>
    _max_concurrent_clients = max_concurrent_clients
    _total_clients_to_spawn = total_clients_to_spawn
    _auth = auth
    _host = host
    _port = port
    _out = out

  be start(listener: Listener) =>
    if not _started then
      _out.print("Starting client spawner.")
      _started = true
      _listener = listener
      _spawn()
    else
      _Unreachable()
    end

  be closed(client: Client) =>
    //_out.print("Client closed.")
    _clients_spawned.unset(client)
    if _should_continue() then
      _spawn()
    end

  be failed(client: Client) =>
    //_out.print("Client failed.")
    _failed = _failed + 1
    _clients_spawned.unset(client)
    if _should_continue() then
      _spawn()
    end

  fun ref _spawn() =>
    while _should_spawn() do
      let c = Client(this, _auth, _host, _port, _out)
      _clients_spawned.set(c)
      _total_clients_spawned = _total_clients_spawned + 1
    end
    _print_progress()
    _try_shutdown()

  fun _should_spawn(): Bool =>
    (_clients_spawned.size() < _max_concurrent_clients.usize()) and
    _should_continue()

  fun _should_continue(): Bool =>
    _total_clients_spawned < _total_clients_to_spawn

  fun _print_progress() =>
    if (_total_clients_spawned % 50_000) == 0 then
      _out.print("Spawned " + _total_clients_spawned.string() + " clients.")
    end

  fun _try_shutdown() =>
    if not _should_continue() then
      _wait_for_shutdown()
    end

  be _wait_for_shutdown() =>
    if (_clients_spawned.size() == 0) and (not _finished) then
      _finished = true
      match _listener
      | let l: Listener =>
        _out.print("All clients spawned and accounted for.")
        _out.print(_failed.string()
          + " connections were unable to be established.")
        l.spawner_done()
      | None =>
        _Unreachable()
      end
    else
      _out.print("Waiting for final clients to finish."
        + _clients_spawned.size().string() + " remaining.")
      _wait_for_shutdown()
    end

actor Client is (TCPConnectionActor & ClientLifecycleEventReceiver)
  """
  Opens a connection.

  Sends a single message and closes when it receives a reply.
  """
  let _spawner: ClientSpawner
  let _out: OutStream
  var _tcp_connection: TCPConnection = TCPConnection.none()

  new create(spawner: ClientSpawner,
    auth: TCPConnectAuth,
    host: String,
    port: String,
    out: OutStream)
  =>
    _spawner = spawner
    _out = out
    _tcp_connection = TCPConnection.client(auth, host, port, "", this, this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _next_lifecycle_event_receiver(): (ClientLifecycleEventReceiver | None) =>
    None

  fun ref on_connected() =>
    //_out.print("Client Connected.")
    _tcp_connection.send("Hi there!")

  fun ref on_connection_failure() =>
    //_out.print("Client Connection Failure.")
    _spawner.failed(this)

  fun ref on_received(data: Array[U8] iso) =>
    _tcp_connection.close()

  fun ref on_closed() =>
    _spawner.closed(this)

primitive _Unreachable
  """
  To be used in places that the compiler can't prove is unreachable but we are
  certain is unreachable and if we reach it, we'd be silently hiding a bug.
  """
  fun apply(loc: SourceLoc = __loc) =>
    @fprintf(
      @pony_os_stderr(),
      ("The unreachable was reached in %s at line %s\n" +
       "Please open an issue at https://github.com/ponylang/lori/issues")
       .cstring(),
      loc.file().cstring(),
      loc.line().string().cstring())
    @exit(1)

primitive _Failed
  """
  Die in a very loud way if we can't get an outgoing connection.
  """
  fun apply(loc: SourceLoc = __loc) =>
    @fprintf(
      @pony_os_stderr(),
      ("Failure in %s at line %s\n" +
       "Please open an issue at https://github.com/ponylang/lori/issues")
       .cstring(),
      loc.file().cstring(),
      loc.line().string().cstring())
    @exit(1)
