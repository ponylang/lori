## Add SSL support

We've added SSL support to Lori. The included support leverages the [ponylang/net_ssl library](https://github.com/ponylang/net_ssl). In addition to net_ssl, you could add custom SSL support by hooking into the same lifecycle hooks that our net_ssl support uses.

Two examples are available in the examples directory. One is a simple echo server that uses SSL and the other an SSL enabled version of our existing "infinite ping-pong" example.

## An SSL library now required to build Lori

With the addition of SSL support, the an SSL library is now a required dependency to build Lori. Ponylang projects support the old OpenSSL 0.9.x API series (now primarily used by LibreSSL) and the newer OpenSSL 1.1.x and 3.x API series.

## Several breaking API changes introduced

As part of adding SSL support, we've introduced several breaking changes that you will have to address when upgrading to this version of Lori.

### `TCPClientActor` removed

We've removed the `TCPClientActor` trait. To mix-in TCP client functionality with an actor, you should replaced `is TCPClientActor` with `is (TCPConnectionActor & ClientLifecycleEventReceiver)`.

### `TCPServerActor` removed

We've removed the `TCPServerActor` trait. To mix-in TCP server functionality with an actor, you should replaced `is TCPServerActor` with `is (TCPConnectionActor & ServerLifecycleEventReceiver)`.

### Lifecycle callbacks are now public

Previously, all lifecycle callbacks were private. For example, in order to hook your actor into the a connection being closed, you implemented the `_on_closed()` method. Now, you should implement the `on_closed()` method. The only difference is the visibility of the method.

We might end up changing back to private methods in the future, but for now, they are public. If [ponyc issue #4613](https://github.com/ponylang/ponyc/issues/4613) is resolved, we will likely switch back to private methods.

## Add callback for when a server is starting up

We've added a callback for when a server is starting up. This callback is called after the server has accepted a connection and before the server starts processing the request. This allows you to any protocol specific setup before the server starts processing the request. For example, this would be where an SSL handshake would be done.

## Add callback for when data is being sent

As part of adding SSL support, we've added the `on_send` callback that can be used to modify outgoing data on send.

## Add callback for when `expect` is called

As part of adding SSL support, we've added the `on_expect_set` callback that is called when `expect` is called.

## Add ability to set TCP keepalive

We've added the method `keepalive` to `TCPConnection`. This method allows you to set the keepalive for the underlying socket.

## Add ability to get local and remote names from a socket

We've added `local_address` and `remote_address` to the `TCPConnection` class. These properties return the local and remote addresses of the socket, respectively.

The return type is the `NetAddress` class from the `net` package in the Pony standard library.

## Allow setting a max connection limit

`TCPListener` now takes an optional limit on the number of accepted connections to have open at a time.

