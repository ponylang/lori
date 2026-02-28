## Allow yielding during socket reads

Under sustained inbound traffic, a single connection's read loop can monopolize the Pony scheduler. `yield_read()` lets the application exit the read loop cooperatively, giving other actors a chance to run. Reading resumes automatically in the next scheduler turn.

Call `yield_read()` from within `_on_received()` to implement any yield policy — message count, byte threshold, time-based, etc.:

```pony
fun ref _on_received(data: Array[U8] iso) =>
  _received_count = _received_count + 1

  // Yield every 10 messages to let other actors run
  if (_received_count % 10) == 0 then
    _tcp_connection.yield_read()
  end
```

Unlike `mute()`/`unmute()`, which persistently stop reading until reversed, `yield_read()` is a one-shot pause — the read loop resumes on its own without explicit action. The library does not impose any built-in yield policy; the application decides when to yield.
