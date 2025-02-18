## Send pending writes on client connect

Previously, when a client connected to a server, we didn't immediately send any
queued writes. This meant that if the client didn't try to send any more data, no data might end up being sent.

We've fixed this bug. Now, when a client connects to a server, we immediately send any queued writes.
