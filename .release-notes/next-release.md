## Fix accept loop spinning on persistent errors

Previously, when `TCPListener`'s accept loop encountered a non-EWOULDBLOCK error (such as running out of file descriptors), it would retry immediately in a tight loop. Since persistent errors like EMFILE never resolve on their own, this caused the listener to spin indefinitely, consuming CPU without making progress.

The accept loop now exits on any error, letting the ASIO event system re-notify the listener. This gives other actors a chance to run and potentially free resources before the next accept attempt.

