## Fix send() reporting a delivered send as rejected

`send()` writes to the socket before it returns. When that write only partly succeeds, it applies backpressure and calls `_on_throttled` right then, inside the `send()` call. If your application closed the connection from `_on_throttled`, the send you had just made could come back as `SendErrorNotConnected` — the error that says the send never took hold — while its bytes were already on the wire. No `_on_sent` and no `_on_send_failed` ever arrived for it. An application that believed the error and retried the send on a new connection handed the peer bytes it already had.

A send accepted in that window now returns a `SendToken` and gets a terminal callback like any other: `_on_sent` when its bytes reach the OS, or `_on_send_failed` when a hard close discards them.

One thing to know about that window: `hard_close()` fires `_on_closed()` synchronously, so an application that hard closes from `_on_throttled` sees `_on_closed` before `send()` hands the token back.
