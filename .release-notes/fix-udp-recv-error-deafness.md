## Fix UDP socket not receiving after transient recvfrom errors

A UDP socket that hit a transient `recvfrom` error (EINTR or similar) stopped receiving datagrams permanently on Linux and Windows. macOS was unaffected.
