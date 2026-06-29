## Replace Windows IOCP socket I/O with readiness notifications

Lori's Windows networking no longer uses I/O completion ports (IOCP). It now uses readiness notifications, the same model Lori already uses on Linux, macOS, and BSD. This follows ponyc, which removed IOCP from its Windows runtime.

Building Lori for Windows now requires ponyc 0.66.0 or later, the release that made this change. Earlier versions of ponyc will not build Lori on Windows. Non-Windows platforms are unaffected and their version requirement is unchanged.

This change has three consequences for Windows, each covered in its own section under this heading: Windows 10 is no longer supported, write backpressure now reflects the real state of the socket, and a muted connection no longer learns that its peer has closed until it is unmuted.

### Drop support for Windows 10

The Windows readiness API (`ProcessSocketNotifications`) exists only on Windows 11 and Windows Server 2022 and later, so the supported Windows floor is now Windows 11 / Windows Server 2022. Windows 10 is no longer supported.

### Windows TCP write backpressure now reflects real socket writability

On Windows, `_on_throttled` and `_on_unthrottled` now fire based on whether the operating system can actually accept more data, matching the other platforms. Previously the decision used an internal heuristic rather than the real state of the socket.

### A muted Windows connection no longer detects peer close until unmuted

On Windows, a muted connection now behaves like every other platform: while muted, it does not learn that its peer has closed until it is unmuted. You **must** call `unmute()` on a muted connection for it to close — without it the connection will never finish closing. Existing Windows code that relied on a muted connection noticing a peer close must now unmute to make progress.

