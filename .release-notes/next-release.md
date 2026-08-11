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

## Make TCPConnection and TCPListener generic over TCPBackend

`TCPConnection`, `TCPListener`, and the related actor and lifecycle receiver traits now take a type parameter `TCP: TCPBackend val = RuntimeBackend`. The default means existing code compiles unchanged — bare `TCPConnection` and `TCPListener` resolve to the `RuntimeBackend` instantiation without a type argument.

`TCPBackend` is a public trait. A test fake that implements it can drive the connection state machine without real sockets. Pony fully reifies generics, so each instantiation compiles to direct calls with no runtime dispatch overhead.

## Rename PonyTCP to RuntimeBackend

`PonyTCP` has been renamed to `RuntimeBackend`. Code that references `PonyTCP` by name should use `RuntimeBackend` instead.

Before:

```pony
PonyTCP.writev_max()
```

After:

```pony
RuntimeBackend.writev_max()
```

