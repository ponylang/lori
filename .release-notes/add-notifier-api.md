## Add notifier-based TCP API subpackage

A new `lori/notifier` subpackage provides a convenience layer over lori's native class-and-trait API. You write a notifier class with the callbacks you care about and hand it to a concrete actor — no actor boilerplate, no trait wiring.

Three actor/notifier pairs cover client connections, server connections, and listeners:

```pony
use "lori"
use "lori/notifier"

class Echo is ServerTCPConnectionNotify
  fun ref on_received(conn: ServerTCPConnection ref, data: Array[U8] iso):
    ReadAction
  =>
    conn.write(consume data)
    KeepReading

class EchoListen is TCPListenNotify
  fun ref on_connected(listen: TCPListener ref):
    ServerTCPConnectionNotify iso^
  =>
    Echo
  fun ref on_not_listening(listen: TCPListener ref) =>
    None

actor Main
  new create(env: Env) =>
    TCPListener(TCPListenAuth(env.root), recover EchoListen end, "", "8989")
```

`write` and `mute` are behaviors rather than synchronous methods, and SSL is configured through a constructor (`.ssl`) rather than a separate class. Use the notifier API for straightforward applications; use lori's native API when you need synchronous send results, custom actor structure, or multiple connections per actor.
