## Fix resource leak from orphaned Happy Eyeballs connections

When `close()` or `hard_close()` was called during the connecting phase, inflight Happy Eyeballs connection attempts could leak file descriptors and ASIO events. On Linux, failed connection attempts delivered error-only events (`ASIO_READ` without `ASIO_WRITE`) that were silently dropped by the writeable guard, preventing cleanup. On macOS, failed sockets produced two events per socket; the old guard accidentally filtered one, but the cleanup still had gaps.

Inflight connections are now reliably drained on all platforms.
