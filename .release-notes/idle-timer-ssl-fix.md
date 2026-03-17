## Fix idle timer issues with SSL connections

The idle timer had two issues with SSL connections:

The timer was being armed when the TCP connection established, before the SSL handshake completed. If an idle timeout was configured before the connection was ready, `_on_idle_timeout()` could fire before `_on_connected()` or `_on_started()`.

Calling `idle_timeout()` on an SSL connection during the handshake could also arm the timer prematurely, producing the same early `_on_idle_timeout()`. Additionally, when the handshake later completed, a second timer was created — leaking the first ASIO timer event.

The idle timer now defers arming until the SSL handshake completes, regardless of whether the timeout is configured before or during the handshake.
