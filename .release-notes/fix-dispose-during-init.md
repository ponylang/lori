## Fix resource leak when disposing a server connection during initialization

Disposing a server-side `TCPConnection` before it finished initializing leaked an ASIO event. The leaked event was noisy, so the runtime would not exit. This could happen when a listener disposed an accepted connection immediately — the dispose could arrive before the connection's deferred initialization, since the two messages come from different actors.
