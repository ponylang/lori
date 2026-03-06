## Make expect() use a constrained type instead of raw USize

`expect()` now takes `(Expect | None)` instead of `USize`. `Expect` is a constrained type that guarantees a value of at least 1. `None` replaces the magic value `0` to mean "deliver all available data." This follows the same pattern used by `IdleTimeout`, `ReadBufferSize`, and `MaxSpawn`.

Before:

```pony
_tcp_connection.expect(4)
_tcp_connection.expect(0)
```

After:

```pony
match MakeExpect(4)
| let e: Expect => _tcp_connection.expect(e)
end
_tcp_connection.expect(None)
```
