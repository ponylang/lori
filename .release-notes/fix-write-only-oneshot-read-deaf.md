## Fix connection going silent after a large write under backpressure

A connection could stop delivering incoming data — `_on_received` would never fire again — after a large write drained under backpressure, when the application kept sending without pausing reads (for example, a relay, proxy, or streaming server). The peer's bytes were acknowledged at the TCP layer but never surfaced to the application, and the connection stayed silent until either side closed it.

A previous fix addressed this for applications that pause reads via `mute()` during backpressure. This completes the fix for applications that send without muting.
