## Fix premature _on_unthrottled during Happy Eyeballs connect

When a client connection succeeded via Happy Eyeballs and the application sent data in `_on_connected` that triggered backpressure (partial write), `_on_unthrottled` was delivered immediately even though the socket was still not writeable and pending data remained unsent. Subsequent `send()` calls would return `SendErrorNotWriteable` despite the application having just been told backpressure was released.

The connection recovers when the next writeable event fires and drains the pending data, but no second `_on_unthrottled` is delivered since the throttle flag was already cleared.

Workaround for older versions: defer sends from `_on_connected` to a subsequent behavior turn so backpressure goes through the normal event path.
