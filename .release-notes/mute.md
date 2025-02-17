## Add ability to mute and unmute a TCP connection

`TCPConnection` now exposes `mute` and `unmute` methods. You can use them to stop and start reading from the connection. While muted, the connection will not read any data from the underlying socket.
