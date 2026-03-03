## Fix read loop not yielding after byte threshold

The POSIX read loop in `TCPConnection` was missing a `return` after scheduling a deferred `_read_again` when the byte threshold was reached. This meant the loop continued reading from the socket in the same behavior call indefinitely under sustained load, preventing per-actor GC from running (GC only runs between behavior invocations) and queuing redundant `_read_again` messages. The read loop now correctly exits after reaching the threshold, allowing GC and other actors to run before resuming.
