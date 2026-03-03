## Change MaxSpawn to a constrained type

`MaxSpawn` is now a constrained type that rejects invalid values at construction time. Previously it was a bare `(U32 | None)` type alias, which meant a limit of 0 would silently create a listener that refused every connection. The new type guarantees the value is at least 1.

The default behavior has also changed. Listeners without an explicit limit now cap at 100,000 concurrent connections (`DefaultMaxSpawn`) rather than having no limit. Pass `None` to get the old unlimited behavior.

```pony
// Before — bare U32, no validation, default unlimited
_tcp_listener = TCPListener(listen_auth, host, port, this where limit = 100)

// After — validated MaxSpawn, default 100,000
match MakeMaxSpawn(100)
| let limit: MaxSpawn =>
  _tcp_listener = TCPListener(listen_auth, host, port, this where limit = limit)
end

// After — unlimited (old default behavior)
_tcp_listener = TCPListener(listen_auth, host, port, this where limit = None)
```
