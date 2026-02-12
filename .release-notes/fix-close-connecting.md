## Fix close() being a no-op during connecting phase

`close()` was silently ignored when called during the Happy Eyeballs connecting phase (before any connection attempt succeeded). The connection attempt would eventually complete cleanup, but no lifecycle callback ever fired — the application called `close()` and never heard back.

`close()` now properly cancels the connecting attempt. Once all in-flight Happy Eyeballs connections have drained, `_on_connection_failure()` fires to notify the application that the connection attempt is done.
