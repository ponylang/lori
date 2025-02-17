## Listener startup bug fixed

There was a bug in the lifecycle handling for `TCPListener` that could cause errors if you called certain methods from the `_on_listening()` and `_on_listen_failed()` callbacks. This has been fixed.
