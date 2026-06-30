## Fix idle timeout closing connections that are still transferring data

A connection could be closed by its idle timeout while it was still actively sending data to a slow peer. The idle timer reset when data was received and when the application called `send()`, but not while buffered data kept draining out to the peer afterward. A large send to a slow reader looked idle — even though bytes were still leaving the socket — and got closed mid-transfer.

The idle timer now resets whenever data is actually written to the socket, including buffered-write drains. A connection is closed by the idle timeout only when no data has moved in either direction for the timeout.

