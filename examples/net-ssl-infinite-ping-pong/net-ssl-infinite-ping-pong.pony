use "collections"
use "files"
use "net_ssl"
use "../../lori"

actor Main
  new create(env: Env) =>
    let file_auth = FileAuth(env.root)
    let sslctx =
      try
        // paths need to be adjusted to a absolute location or you need to run
        // the example from a location where this relative path will be valid
        // aka the root of this project
        recover
          SSLContext
            .> set_authority(
              FilePath(file_auth, "assets/cert.pem"))?
            .> set_cert(
              FilePath(file_auth, "assets/cert.pem"),
              FilePath(file_auth, "assets/key.pem"))?
            .> set_client_verify(false)
            .> set_server_verify(false)
        end
      else
        env.out.print("unable to set up SSL authentication")
        return
      end

    let listen_auth = TCPListenAuth(env.root)
    let connect_auth = TCPConnectAuth(env.root)
    Listener(listen_auth, connect_auth, consume sslctx, env.out)

actor  Listener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _out: OutStream
  let _connect_auth: TCPConnectAuth
  let _server_auth: TCPServerAuth
  let _sslctx: SSLContext

  new create(listen_auth: TCPListenAuth,
    connect_auth: TCPConnectAuth,
    sslctx: SSLContext,
    out: OutStream)
  =>
    _connect_auth = connect_auth
    _out = out
    _server_auth = TCPServerAuth(listen_auth)
    _sslctx = sslctx
    _tcp_listener = TCPListener(listen_auth, "127.0.0.1", "7669", this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): Server ? =>
    try
      Server(_server_auth, _sslctx.server()?, fd, _out)
    else
      _out.print("unable to set up incoming SSL connection")
      error
    end

  fun ref _on_listening() =>
    try
      Client(_connect_auth, _sslctx.client()?, "127.0.0.1", "7669", "", _out)
    else
      _out.print("unable to set up outgoing SSL connection")
    end

  fun ref _on_listen_failure() =>
    _out.print("Unable to open listener")

actor Server is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _out: OutStream

  new create(auth: TCPServerAuth, ssl: SSL iso, fd: U32, out: OutStream) =>
    _out = out
    let sslc = NetSSLServerConnection(consume ssl, this)
    _tcp_connection =  TCPConnection.server(auth, fd, this, sslc)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _next_lifecycle_event_receiver(): None =>
    None

  fun ref _on_received(data: Array[U8] iso) =>
    _out.print(consume data)
    _tcp_connection.send("Pong")

actor Client is (TCPConnectionActor & ClientLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _out: OutStream

  new create(auth: TCPConnectAuth,
    ssl: SSL iso,
    host: String,
    port: String,
    from: String,
    out: OutStream)
  =>
    _out = out
    let sslc = NetSSLClientConnection(consume ssl, this)
    _tcp_connection = TCPConnection.client(auth, host, port, from, this, sslc)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _next_lifecycle_event_receiver(): None =>
    None

  fun ref _on_connected() =>
   _tcp_connection.send("Ping")

  fun ref _on_received(data: Array[U8] iso) =>
   _out.print(consume data)
   _tcp_connection.send("Ping")
