## Fix hard_close() being a no-op during connecting phase

`hard_close()` was silently ignored when called during the Happy Eyeballs connecting phase (before any connection attempt succeeded). If a connection attempt later succeeded, the connection would go live as if `hard_close()` was never called.

`hard_close()` now properly cancels the connecting attempt. It marks the connection as closed so that any subsequent Happy Eyeballs successes are cleaned up instead of establishing a live connection, and fires `_on_connection_failure()` to notify the application.
