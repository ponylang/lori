## Send TLS close_notify on graceful close

Calling `close()` on a TLS connection now sends a `close_notify` alert before closing the TCP connection. Without it, the peer cannot tell a clean shutdown from a truncated stream (RFC 8446 section 6.1).

When a peer sends `close_notify`, the connection now closes gracefully instead of tearing down immediately -- pending writes complete before the connection closes.

