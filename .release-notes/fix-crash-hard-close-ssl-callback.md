## Fix a crash when hard closing an SSL connection from a callback

Calling `hard_close()` on an SSL connection from inside one of its own lifecycle callbacks — `_on_received`, `_on_connected`, `_on_started`, or `_on_tls_ready` — crashed the process. Dropping a connection the moment its handshake finished, or closing one as soon as you read a message you won't serve, was enough to trigger it.

Hard closing an SSL connection from any of those callbacks now shuts it down cleanly. Any decrypted messages still undelivered from the same read are dropped, which is what closing the connection asked for. Graceful `close()` was never affected, and neither were plaintext connections.
