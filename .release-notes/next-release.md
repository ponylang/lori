## Handle ASIO_ERROR notifications from ponyc runtime

ponyc 0.63.1 introduced `ASIO_ERROR` notifications that fire when an event subscription fails (e.g. kqueue/epoll returns ENOMEM). Without handling, these notifications were silently dropped, potentially leaving connections or listeners in a stuck state.

Lori now handles `ASIO_ERROR` across all event categories:

- **TCPListener**: Closes the listener when its event subscription fails.
- **TCPConnection own events**: Hard-closes the connection when its socket event subscription fails.
- **TCPConnection foreign events**: Treats errored Happy Eyeballs events as failed connection attempts during connecting, or as stragglers in other states.
- **TCPConnection timer events**: Connect timer errors abort the connection with `ConnectionFailedTimerError`. Idle timer and user timer errors cancel the timer silently.

A new `ConnectionFailedTimerError` failure reason has been added to `ConnectionFailureReason`. If you match exhaustively on `ConnectionFailureReason`, you'll need to add a case for the new variant:

```pony
match \exhaustive\ reason
| ConnectionFailedDNS => // ...
| ConnectionFailedTCP => // ...
| ConnectionFailedSSL => // ...
| ConnectionFailedTimeout => // ...
| ConnectionFailedTimerError => // ...
end
```

Requires ponyc 0.63.1 or later.
