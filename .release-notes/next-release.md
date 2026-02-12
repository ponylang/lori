## Fix spurious _on_connection_failure() after hard_close()

The 0.8.0 fixes for `hard_close()` and `close()` during the connecting phase introduced a regression: `_on_connection_failure()` could fire spuriously after `hard_close()` completed on an already-connected session. Applications would receive `_on_connection_failure()` after `_on_closed()` had already fired, which is an invalid callback sequence.

