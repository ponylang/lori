## Add UDP socket support

Lori now supports UDP alongside TCP. `UDPSocket` follows the same class-in-actor pattern as `TCPConnection`: the I/O state machine lives in a plain class that your actor holds and delegates to.

A UDP application implements `UDPSocketActor` and `UDPLifecycleEventReceiver`, provides `_socket()` returning the `UDPSocket`, and receives callbacks for `_on_bound`, `_on_bind_failure`, `_on_received`, and `_on_closed`.

```pony
use "lori"
use net = "net"

actor UDPEchoServer is (UDPSocketActor & UDPLifecycleEventReceiver)
  var _udp: UDPSocket = UDPSocket.none()

  new create(auth: UDPAuth, host: String, port: String) =>
    _udp = UDPSocket(auth, host, port, this, this)

  fun ref _socket(): UDPSocket =>
    _udp

  fun ref _on_bind_failure() =>
    None

  fun ref _on_received(data: Array[U8] iso, from: net.NetAddress val)
    : ReadAction
  =>
    _udp.send_to(consume data, from)
    KeepReading
```

`send_to` returns a `SendToResult` union: `SendToOk` when the datagram was handed to the OS, `SendToWouldBlock` when the send buffer is full, `SendToError` on an unrecoverable error, or `SendToNotOpen` when the socket is not bound. UDP sends are synchronous and all-or-nothing.

`_on_received` returns a `ReadAction`, the same as TCP. The read loop also yields after processing a buffer's worth of bytes or the per-turn datagram ceiling (256 by default).

`UDPAuth` is made from `AmbientAuth` or `NetAuth`.

