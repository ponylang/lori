## Require ponyc 0.67.0 to fix a possible write hang under load

Under write load, a socket write could hang the whole program. When the send buffer filled on a blocking file descriptor, the write stalled and never returned. Connections use non-blocking descriptors, so this was only reachable once the operating system had reused a closed connection's descriptor number for a blocking socket elsewhere in the process — rare, but possible.

Sends now use a socket call, new in ponyc 0.67.0, that returns when the send buffer is full instead of stalling. Lori therefore requires ponyc 0.67.0 or later. The hang is closed on Linux, FreeBSD, OpenBSD, and DragonFly; macOS and Windows are unchanged.
