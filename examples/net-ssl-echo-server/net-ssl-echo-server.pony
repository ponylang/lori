use "files"
use "ssl/net"
use "../../lori"

actor Main
  new create(env: Env) =>
    let file_auth = FileAuth(env.root)
    let sslctx =
      try
        // paths need to be adjusted to a absolute location or you need to run
        // the example from a location where this relative path will be valid
        // aka the root of this project
        recover val
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

    let auth = TCPListenAuth(env.root)
    let echo = EchoServer(auth, sslctx, "", "7669", env.out)

actor EchoServer is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _out: OutStream
  let _server_auth: TCPServerAuth
  let _sslctx: SSLContext val

  new create(listen_auth: TCPListenAuth,
    sslctx: SSLContext val,
    host: String,
    port: String,
    out: OutStream)
  =>
    _out = out
    _sslctx = sslctx
    _server_auth = TCPServerAuth(listen_auth)
    _tcp_listener = TCPListener(listen_auth, host, port, this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): Echoer =>
    Echoer(_server_auth, _sslctx, fd, _out)

  fun ref _on_closed() =>
    _out.print("Echo server shut down.")

  fun ref _on_listen_failure() =>
    _out.print("Couldn't start Echo server. " +
      "Perhaps try another network interface?")

  fun ref _on_listening() =>
    _out.print("Echo server started.")

actor Echoer is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _out: OutStream

  new create(auth: TCPServerAuth, sslctx: SSLContext val, fd: U32,
    out: OutStream)
  =>
    _out = out
    _tcp_connection = TCPConnection.ssl_server(auth, sslctx, fd, this, this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_closed() =>
    _out.print("Connection Closed")

  fun ref _on_received(data: Array[U8] iso) =>
    _out.print("Decrypted Data received. Echoing it back.")
    _connection().send(consume data)
