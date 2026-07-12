## Remove is_open() from TCPConnection

`TCPConnection.is_open()` is gone. It could not answer either question you would have reached for it to answer.

`is_open()` was true in two states: a connection that was open, and one part-way through a TLS upgrade started by `start_tls()`. During that upgrade the connection was "open" and `send()` refused the data anyway, so a true reading did not mean you could send. And it was false while a connection was still being established — a connection that might yet take everything you had for it. So neither reading told you what you could do with the connection.

Two predicates do. `is_writeable()` says the connection takes a `send()` right now: on a plaintext connection that means `send()` returns a `SendToken`, and on an SSL connection the session can still reject the write. `is_closed()` says no send will ever be accepted again, so data you are holding for it can be dropped. Neither one true means hold the data: the connection is still connecting, still handshaking, or under backpressure. It resolves either way — with `_on_connected`, `_on_started`, `_on_tls_ready` or `_on_unthrottled` when it becomes writeable, or with a failure callback, after which `is_closed()` is true and you can drop the data. Both true at once cannot happen.

```pony
// Before
if _tcp_connection.is_open() then
  _tcp_connection.send(consume data)
end

// After
if _tcp_connection.is_writeable() then
  // On an SSL connection, match send()'s return: the session can still
  // reject the write, and send() takes the buffer either way.
  _tcp_connection.send(consume data)
end
```

If you called `is_open()` before `set_timer()` or a socket option, drop the check and read the return value. `set_timer()` returns `SetTimerNotOpen` and the socket option methods return an error value, so they already tell you.
