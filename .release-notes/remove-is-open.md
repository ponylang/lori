## Remove is_open() from TCPConnection

`is_open()` has been removed from `TCPConnection`. Code that queried connection state before acting should instead call the operation directly and handle the result.

Before:

```pony
if _tcp_connection.is_open() then
  _tcp_connection.send(data)
end
```

After:

```pony
match _tcp_connection.send(data)
| SendAccepted => // sent
| SendErrorNotConnected => // not connected or closed
| SendErrorNotWriteable => // backpressure
end
```
