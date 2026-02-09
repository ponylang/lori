## Fix OutgoingFails test hanging on WSL2 with mirrored networking

The `OutgoingFails` test would hang on WSL2 when using mirrored networking mode due to a [WSL2 bug](https://github.com/microsoft/WSL/issues/10855) where RST packets for connections to closed ports on `127.0.0.1` have a corrupted destination port. On Linux, the test now connects to `127.0.0.2` instead, which stays within the Linux kernel and gets an immediate connection refusal.
