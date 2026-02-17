"""
Demonstrates lori's expect() for length-prefixed message framing and
multi-buffer send() for sending header + payload in a single writev syscall.

A framed client connects to an echo server and exchanges messages using a
simple protocol: each message is preceded by a 4-byte big-endian length
header. The server uses expect() to switch between reading the 4-byte header
and reading the variable-length payload, then echoes each message back with
the same framing. The client uses the same expect()-based framing to read
echoed responses.

Expected output shows the client sending several messages and receiving each
one echoed back, confirming the framing round-trip.
"""
use "../../lori"

actor Main
  new create(env: Env) =>
    Listener(TCPListenAuth(env.root), TCPConnectAuth(env.root), env.out)

actor Listener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _out: OutStream
  let _connect_auth: TCPConnectAuth
  let _server_auth: TCPServerAuth

  new create(listen_auth: TCPListenAuth,
    connect_auth: TCPConnectAuth,
    out: OutStream)
  =>
    _connect_auth = connect_auth
    _out = out
    _server_auth = TCPServerAuth(listen_auth)
    _tcp_listener = TCPListener(listen_auth, "127.0.0.1", "7670", this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): FramedServer =>
    FramedServer(_server_auth, fd, _out)

  fun ref _on_listening() =>
    _out.print("Listener ready, launching framed client...")
    FramedClient(_connect_auth, "127.0.0.1", "7670", _out)

  fun ref _on_listen_failure() =>
    _out.print("Unable to open listener")

actor FramedServer is (TCPConnectionActor & ServerLifecycleEventReceiver)
  """
  Server-side connection that reads length-prefixed messages and echoes them
  back with the same framing. Uses expect() to switch between reading the
  4-byte header and the variable-length payload.
  """
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _out: OutStream
  var _reading_header: Bool = true

  new create(auth: TCPServerAuth, fd: U32, out: OutStream) =>
    _out = out
    _tcp_connection = TCPConnection.server(auth, fd, this, this)
    try _tcp_connection.expect(4)? end

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_received(data: Array[U8] iso) =>
    if _reading_header then
      try
        let len = (data(0)?.usize() << 24) or
          (data(1)?.usize() << 16) or
          (data(2)?.usize() << 8) or
          data(3)?.usize()
        _out.print("Server: header says " + len.string() + " byte payload")
        _reading_header = false
        try _tcp_connection.expect(len)? end
      end
    else
      let payload: Array[U8] val = consume data
      let len = payload.size()
      _out.print("Server: echoing \"" + String.from_array(payload) + "\"")

      // Echo back with same framing: header + payload in one writev syscall
      let header = recover val
        let h = Array[U8](4)
        h.push((len >> 24).u8())
        h.push((len >> 16).u8())
        h.push((len >> 8).u8())
        h.push(len.u8())
        h
      end
      _tcp_connection.send(recover val [as ByteSeq: header; payload] end)

      _reading_header = true
      try _tcp_connection.expect(4)? end
    end

  fun ref _on_closed() =>
    _out.print("Server: connection closed")

actor FramedClient is (TCPConnectionActor & ClientLifecycleEventReceiver)
  """
  Client that sends length-prefixed messages and reads back echoed responses
  using the same framing protocol.
  """
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _out: OutStream
  let _messages: Array[String] val
  var _reading_header: Bool = true
  var _messages_received: USize = 0

  new create(auth: TCPConnectAuth, host: String, port: String,
    out: OutStream)
  =>
    _out = out
    _messages = recover val
      let m = Array[String](3)
      m.push("Hello")
      m.push("Framing!")
      m.push("Length-prefixed protocols are neat")
      m
    end
    _tcp_connection = TCPConnection.client(auth, host, port, "", this, this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _out.print("Client: connected, sending " + _messages.size().string()
      + " framed messages...")
    for msg in _messages.values() do
      _send_framed(msg)
    end
    try _tcp_connection.expect(4)? end

  fun ref _send_framed(msg: String) =>
    """
    Send a message with a 4-byte big-endian length prefix, sending both
    header and payload in a single writev syscall.
    """
    let len = msg.size()
    let header = recover val
      let h = Array[U8](4)
      h.push((len >> 24).u8())
      h.push((len >> 16).u8())
      h.push((len >> 8).u8())
      h.push(len.u8())
      h
    end
    _tcp_connection.send(recover val [as ByteSeq: header; msg] end)

  fun ref _on_received(data: Array[U8] iso) =>
    if _reading_header then
      try
        let len = (data(0)?.usize() << 24) or
          (data(1)?.usize() << 16) or
          (data(2)?.usize() << 8) or
          data(3)?.usize()
        _reading_header = false
        try _tcp_connection.expect(len)? end
      end
    else
      let payload = String.from_array(consume data)
      _messages_received = _messages_received + 1
      try
        let expected = _messages(_messages_received - 1)?
        if payload == expected then
          _out.print("Client: echo " + _messages_received.string()
            + "/" + _messages.size().string() + ": \"" + payload + "\"")
        else
          _out.print("Client: mismatch! expected \"" + expected
            + "\" got \"" + payload + "\"")
        end
      end

      _reading_header = true
      try _tcp_connection.expect(4)? end

      if _messages_received == _messages.size() then
        _out.print("Client: all " + _messages.size().string()
          + " messages echoed successfully")
        _tcp_connection.close()
      end
    end

  fun ref _on_connection_failure() =>
    _out.print("Client: connection failed")

  fun ref _on_closed() =>
    _out.print("Client: closed")
