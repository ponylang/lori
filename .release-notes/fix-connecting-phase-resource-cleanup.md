## Fix resource leak from orphaned Happy Eyeballs connections

When a client connection was closed or timed out during the Happy Eyeballs connecting phase, inflight connection attempts that hadn't completed yet could be orphaned — their socket file descriptors and ASIO events were never cleaned up. This could cause the Pony runtime to hang on shutdown because leaked ASIO events kept the event loop alive.

The fix ensures all inflight connection attempts are properly drained and cleaned up before the connection fully closes, regardless of how the close was initiated (user `close()`, `hard_close()`, or connection timeout).
