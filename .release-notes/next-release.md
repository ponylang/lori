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

`TCPConnection`, `TCPListener`, and the related actor and lifecycle receiver traits now take a type parameter `TCP: TCPBackend ref = RuntimeBackend`. The default means existing code compiles unchanged — bare `TCPConnection` and `TCPListener` resolve to the `RuntimeBackend` instantiation without a type argument.

`TCPBackend` is a public trait. A test fake that implements it can drive the connection state machine without real sockets. Pony fully reifies generics, so each instantiation compiles to direct calls with no runtime dispatch overhead.

## Rename PonyTCP to RuntimeBackend

`PonyTCP` has been renamed to `RuntimeBackend` and changed from a primitive to a class. Code that references `PonyTCP` by name should use `RuntimeBackend` instead.

Before:

```pony
PonyTCP.writev_max()
```

After:

```pony
RuntimeBackend.writev_max()
```

## Fix resource leak when disposing a server connection during initialization

Disposing a server-side `TCPConnection` before it finished initializing leaked an ASIO event. The leaked event was noisy, so the runtime would not exit. This could happen when a listener disposed an accepted connection immediately — the dispose could arrive before the connection's deferred initialization, since the two messages come from different actors.

## Several TCPConnection and TCPListener methods now require a ref receiver

`TCPConnection.keepalive`, `TCPConnection.local_address`, `TCPConnection.remote_address`, and `TCPListener.local_address` are now `fun ref` instead of `fun box`. Code that calls any of these through a `box` reference needs a `ref` reference instead.

