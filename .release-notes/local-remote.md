## Add ability to get local and remote names from a socket

We've added `local_address` and `remote_address` to the `TCPConnection` class. These properties return the local and remote addresses of the socket, respectively.

The return type is the `NetAddress` class from the `net` package in the Pony standard library.
