## Add optional connection timeout for client connections

Client connection attempts can now be bounded with a timeout that covers the TCP Happy Eyeballs phase and (for SSL connections) the TLS handshake. Pass a `ConnectionTimeout` to the `client` or `ssl_client` constructor:

```pony
match MakeConnectionTimeout(5_000)
| let ct: ConnectionTimeout =>
  _tcp_connection = TCPConnection.client(auth, host, port, "", this, this
    where connection_timeout = ct)
end
```

If the timeout fires before `_on_connected`, the connection fails with `ConnectionFailedTimeout` in `_on_connection_failure`. The timeout is disabled by default (`None`).

## Expand ConnectionFailureReason with ConnectionFailedTimeout

`ConnectionFailureReason` now includes `ConnectionFailedTimeout`. This is a breaking change — exhaustive matches on `ConnectionFailureReason` must add a branch for the new variant:

Before:

```pony
match reason
| ConnectionFailedDNS => // ...
| ConnectionFailedTCP => // ...
| ConnectionFailedSSL => // ...
end
```

After:

```pony
match reason
| ConnectionFailedDNS => // ...
| ConnectionFailedTCP => // ...
| ConnectionFailedSSL => // ...
| ConnectionFailedTimeout => // ...
end
```
