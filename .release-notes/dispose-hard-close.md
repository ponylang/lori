## Fix dispose() hanging when peer FIN is missed

`TCPConnectionActor.dispose()` previously called `close()`, which does a graceful half-close — it sends a FIN and waits for the peer to acknowledge before fully cleaning up. On POSIX with edge-triggered oneshot events, the peer's FIN notification can be missed in a narrow timing window after resubscription, leaving the socket stuck in CLOSE_WAIT and preventing the runtime from exiting.

`dispose()` now calls `hard_close()`, which immediately unsubscribes from ASIO, closes the fd, and fires `_on_closed()`. This matches what callers expect from disposal: unconditional teardown, not a protocol exchange. Applications that need a graceful close should call `close()` explicitly before disposal.
