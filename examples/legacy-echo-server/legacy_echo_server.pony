"""
Echo server using the Legacy stdlib-net compatibility API.

This mirrors the shape of a Pony standard library `net` package echo server —
notifier objects, a listener, and a per-connection notifier — but runs on lori.
It shows how code written against the old `net.TCPListener` /
`net.TCPConnection` API moves to lori with small changes: the notifier's `conn`
parameter becomes `LegacyTCPConnection`, `is TCPConnectionNotify` becomes
`is LegacyTCPConnectionNotify`, and a client (not shown here) is created with
`LegacyTCPClient` instead of constructing `TCPConnection` directly.

Unlike lori's native API (see the `echo-server` example), the application logic
lives in notifier classes rather than in your own actor. That is the point of
this API: it keeps the old programming model so existing code needs less
rework.

Connect with any TCP client (e.g. `netcat localhost 7679`) and type to see your
input echoed back.
"""
use "../../lori"

actor Main
  new create(env: Env) =>
    LegacyTCPListener(
      TCPListenAuth(env.root), EchoListener(env.out), "", "7679")

class EchoListener is LegacyTCPListenNotify
  """
  Reports listener lifecycle and builds an echo notifier for each connection.
  """
  let _out: OutStream

  new iso create(out: OutStream) =>
    _out = out

  fun ref listening(listen: LegacyTCPListener ref) =>
    _out.print("Echo server started.")

  fun ref not_listening(listen: LegacyTCPListener ref) =>
    _out.print("Couldn't start echo server. " +
      "Perhaps try another network interface?")

  fun ref connected(listen: LegacyTCPListener ref)
    : LegacyTCPConnectionNotify iso^
  =>
    EchoConnection(_out)

  fun ref closed(listen: LegacyTCPListener ref) =>
    _out.print("Echo server shut down.")

class EchoConnection is LegacyTCPConnectionNotify
  """
  Echoes received data back to the client.
  """
  let _out: OutStream

  new iso create(out: OutStream) =>
    _out = out

  fun ref accepted(conn: LegacyTCPConnection ref) =>
    _out.print("Connection accepted.")

  fun ref received(
    conn: LegacyTCPConnection ref,
    data: Array[U8] iso,
    times: USize)
    : Bool
  =>
    _out.print("Data received. Echoing it back.")
    conn.write(consume data)
    true

  fun ref closed(conn: LegacyTCPConnection ref) =>
    _out.print("Connection closed.")

  fun ref connect_failed(conn: LegacyTCPConnection ref) =>
    None
