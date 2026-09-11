# Lori

Lori is now part of ponyc's standard library as the `net` package.

Lori was a networking library for Pony that separated connection logic from actor scheduling — the networking state machine lived in a plain class (`TCPConnection`, `UDPSocket`) that your actor delegated to, rather than baking everything into a single actor. It gave you control over how your actor was structured while lori handled the low-level I/O.

This repository is archived. For the current code, see the [`net` package in ponyc](https://github.com/ponylang/ponyc/tree/main/packages/net).
