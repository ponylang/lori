## Fix graceful close dropping writes queued under backpressure

When a connection was under write backpressure — bytes you sent were queued because the socket couldn't take them yet — a graceful `close()` dropped those queued bytes. They never reached the peer, and their sends completed with `_on_send_failed` instead of `_on_sent`, even though you closed the connection cleanly rather than aborting it.

A graceful `close()` now sends what is still queued before shutting the connection down, so the data you handed to an accepted `send()` goes out rather than being dropped, and those sends fire `_on_sent`. `hard_close()` is unchanged: it still drops queued writes and fails their sends with `_on_send_failed`.
