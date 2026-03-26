## Use prebuilt LibreSSL binaries on Windows

The `libs` command has been removed from `make.ps1`. CI now downloads prebuilt LibreSSL static libraries directly from the [LibreSSL GitHub releases](https://github.com/libressl/portable/releases) instead of building from source. Windows users who were using `make.ps1 -Command libs` to build LibreSSL locally can download prebuilt binaries from the same location. Prebuilt binaries are available for x86-64 and ARM64.

## Fix crash when dispose() arrives before connection initialization

Calling `dispose()` on a connection actor before its internal initialization completed would crash with an unreachable state error. This could happen because `_finish_initialization` is a self-to-self message queued during the actor's constructor, while `dispose()` arrives from an external actor — and Pony's causal messaging provides no ordering guarantee between different senders. The race is unlikely but was observed on macOS arm64 CI.

