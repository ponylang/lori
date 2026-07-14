## Add a compatibility API for moving code from the standard library net package

lori now includes `LegacyTCPClient`, `LegacyTCPListener`, and matching notifier interfaces that recreate the standard library `net` package's API on top of lori. If you have code written against `net.TCPConnection` and `net.TCPListener`, this lets you move it to lori with mechanical changes rather than a rewrite: the application logic stays in notifier objects, the way the standard library does it.

```pony
use "lori"

actor Main
  new create(env: Env) =>
    LegacyTCPListener(TCPListenAuth(env.root), EchoListener, "", "8989")

class EchoListener is LegacyTCPListenNotify
  fun ref connected(listen: LegacyTCPListener ref)
    : LegacyTCPConnectionNotify iso^
  =>
    EchoConnection

class EchoConnection is LegacyTCPConnectionNotify
  fun ref received(
    conn: LegacyTCPConnection ref,
    data: Array[U8] iso,
    times: USize)
    : Bool
  =>
    conn.write(consume data)
    true

  fun ref connect_failed(conn: LegacyTCPConnection ref) =>
    None
```

SSL is covered by `LegacySSLConnection`, matching the `ssl/net` package's `SSLConnection` decorator. Moving code over needs a few changes — the notifier's `conn` parameter becomes `LegacyTCPConnection`, and clients are created with `LegacyTCPClient` instead of `TCPConnection` — and a few behaviors differ. The package documentation lists them.
