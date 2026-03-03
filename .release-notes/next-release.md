## Fix accept loop spinning on persistent errors

Previously, when `TCPListener`'s accept loop encountered a non-EWOULDBLOCK error (such as running out of file descriptors), it would retry immediately in a tight loop. Since persistent errors like EMFILE never resolve on their own, this caused the listener to spin indefinitely, consuming CPU without making progress.

The accept loop now exits on any error, letting the ASIO event system re-notify the listener. This gives other actors a chance to run and potentially free resources before the next accept attempt.

## Fix read loop not yielding after byte threshold

The POSIX read loop in `TCPConnection` was missing a `return` after scheduling a deferred `_read_again` when the byte threshold was reached. This meant the loop continued reading from the socket in the same behavior call indefinitely under sustained load, preventing per-actor GC from running (GC only runs between behavior invocations) and queuing redundant `_read_again` messages. The read loop now correctly exits after reaching the threshold, allowing GC and other actors to run before resuming.

