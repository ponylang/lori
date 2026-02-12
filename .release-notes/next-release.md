## Add first-class LibreSSL support

LibreSSL is now a first-class supported SSL library. LibreSSL users previously had to build with `ssl=0.9.0`, which forced LibreSSL through a code path designed for ancient OpenSSL. This silently disabled ALPN negotiation, PBKDF2 key derivation, and the modern EVP/init APIs that LibreSSL supports.

Projects that build against LibreSSL should switch from `ssl=0.9.0` to `ssl=libressl`.

This change comes via an update to ponylang/ssl 2.0.0.

## Drop OpenSSL 0.9.0 support

OpenSSL 0.9.0 is no longer supported. The `ssl=0.9.0` build option and the `-Dopenssl_0.9.0` define have been removed. LibreSSL users who previously used `ssl=0.9.0` should switch to `ssl=libressl`.

This change comes via an update to ponylang/ssl 2.0.0.
## Fix hard_close() being a no-op during connecting phase

`hard_close()` was silently ignored when called during the Happy Eyeballs connecting phase (before any connection attempt succeeded). If a connection attempt later succeeded, the connection would go live as if `hard_close()` was never called.

`hard_close()` now properly cancels the connecting attempt. It marks the connection as closed so that any subsequent Happy Eyeballs successes are cleaned up instead of establishing a live connection, and fires `_on_connection_failure()` to notify the application.

