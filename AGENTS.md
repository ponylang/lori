# Lori

A Pony TCP networking library. It reworks the standard library's `net` package around a different split: the connection logic lives in a plain `class` (`TCPConnection`, `TCPListener`) that the user's `actor` holds and delegates to, rather than being baked into a single actor.

<!-- contributor-only -->
## Contributing with an AI assistant

This is a Pony project. The ponylang org maintains a set of LLM coding skills. Get set up with them before contributing:

- **Not set up yet?** Install them once:

  ```bash
  git clone https://github.com/ponylang/llm-skills.git
  cd llm-skills
  python install.py
  ```

- **Already set up?** Make sure you're on the latest. If you installed with the script above, `git pull` in the directory where you cloned `llm-skills` and the symlinked skills update automatically — if you set them up another way, refresh them however that setup expects.

See the [llm-skills README](https://github.com/ponylang/llm-skills) for details and other harnesses.

When you start working on this project, load the `pony-skills` skill — it tells your assistant which Pony skill to use for each task.

Read [CONTRIBUTING.md](CONTRIBUTING.md).
<!-- /contributor-only -->

## Building and testing

```
make ssl=3.0.x                       # build + run unit tests (test is the default target)
make test-one t=TestName ssl=3.0.x   # run a single test by name
make ci ssl=3.0.x                    # unit tests + build examples + build stress tests
make examples ssl=3.0.x              # build all examples
make stress-tests ssl=3.0.x          # build stress tests
make config=debug ssl=3.0.x          # debug build
make clean                           # clean build artifacts + corral deps
make lint                            # run pony-lint over the repo (no ssl= needed)
```

`ssl=` is required on every build and test target, set to your installed TLS library: `3.0.x`, `4.0.x`, `1.1.x`, or `libressl` (OpenSSL 3.x → `ssl=3.0.x`). `make` runs `corral fetch` before compiling.

Windows builds and tests through `make.ps1`, not the Makefile. A build or test change has to go in both.

## Architecture

`TCPConnection` (class) holds all TCP and SSL state and I/O logic and is not an actor. The user writes an actor that implements the `TCPConnectionActor` trait together with one of the two lifecycle-event-receiver traits, `ClientLifecycleEventReceiver` or `ServerLifecycleEventReceiver`, which carry the `_on_*` callbacks. `TCPListener`/`TCPListenerActor` are the same split for the accept side.

### Connection lifecycle

`TCPConnection` tracks its lifecycle with explicit state objects — the `_ConnectionState` trait and its implementers in `_connection_state.pony` — rather than boolean flags.

```
_ConnectionNone → _ClientConnecting → _Open → _Closing → _Closed
                                    ↘ _Closed (hard_close)
_ClientConnecting → _SSLHandshaking → _Open (ssl_handshake_complete)
                                    ↘ _Closed (hard_close / SSL error)
_ClientConnecting → _UnconnectedClosing → _Closed (close, drain stragglers)
_ClientConnecting → _Closed (hard_close / all connections failed)
_ConnectionNone → _Open (server, plaintext) → _Closing → _Closed
_ConnectionNone → _SSLHandshaking (server, SSL) → _Open (ssl_handshake_complete)
_ConnectionNone → _Closed (SSL session creation failed)
_Open → _TLSUpgrading (start_tls) → _Open (ssl_handshake_complete)
                                   ↘ _Closed (hard_close / TLS error)
```

Design: Discussion #219.

## Traps

Designs that were tried, or are tempting, and why lori does not use them — the one thing the code cannot tell you, because it only records what it does now.

- **One read loop; keep delivery out of `_ssl_poll()`.** Every read-side control (mute, liveness) lives in the single `_read()` loop exactly once. An earlier design had `_ssl_poll()` deliver to the application from a second loop of its own, so each control had to be written twice — and two shipped as bugs before the second copy existed: the liveness check (segfault, PR #311) and mute (issue #313). `_ssl_poll()` flushes protocol output; it does not deliver.

- **`_ssl` is a `_TLSState`, not `(SSL | None)`.** Its four variants — `_NoTLS`, `_TLS`, `_TLSDisposed`, `_TLSFailed` — separate "is this TLS?" from "may I use the session?", which an `Option` cannot: with the field cleared, `_next_message()` and `_fill()` take their plaintext branches and hand the application ciphertext; with it kept, `match` binds a disposed session behind what looks like a guard. That ambiguity was PR #311's segfault. Dispose only through `_dispose_tls()`, which disposes and moves to `_TLSDisposed` in one step — disposing without moving leaves `_TLS` binding a dead session.

- **Mint the send token before the flush.** `_do_send` mints the `SendToken` and queues it before flushing, so every accepted send gets one terminal callback (`_on_sent` or `_on_send_failed`) whatever the flush does — and the flush can close the connection. Minting after the flush loses the callback for a send whose bytes the flush already wrote. Every error return stays upstream of the mint, so an errored send burns no token id.

- **The hard-close reason is the `_HardCloseCause` argument, not a field.** `_hard_close(cause)` carries why the close happened. An earlier design set one of three fields (`_connect_timed_out` and the like) right before an argumentless `hard_close()` and dug it back out after. Do not add a fourth field, and do not push the no-distinguishing-cause case out to a `None` beside the type — `_UnspecifiedCause` is a real variant, so every hard-close path can match the cause in full.

- **The yield decision is the callback's return value, not a field.** `_on_received` returns `KeepReading` or `YieldReading`, and `_read()` acts on the returned value. An earlier design stored the answer in a `_yield_read` field, which made the one spot where the loop read that field load-bearing. Do not put the decision back in a field.

- **STARTTLS refuses buffered read data (CVE-2021-23222).** `start_tls()` requires the connection open, not already TLS, not muted, no buffered read data, and no pending writes. The no-buffered-data precondition is there for the CVE; do not relax it.

## Platform differences

POSIX and Windows share one readiness-based I/O path: one-shot readiness events (epoll/kqueue; `ProcessSocketNotifications` on Windows), resubscribe, then a synchronous `PonyTCP.receive`/`sendv`. Windows uses this path because ponyc removed IOCP; the floor is Windows 11 / Windows Server 2022. Two rules stay platform-specific — the vectored-send batch size (`PonyTCP.writev_max()`) and closing a subscribed fd (`_close_event_fd()`, POSIX-only) — both documented at those functions.

## Conventions

- Follows the [Pony standard library Style Guide](https://github.com/ponylang/ponyc/blob/main/STYLE_GUIDE.md).
- `_Unreachable()` in a branch the compiler cannot prove impossible, rather than an empty `else`.
- A test listener must keep a reference to every actor it creates in `_on_accept`/`_on_listening` and dispose each one in `_on_closed`. The runtime will not exit while actors hold live I/O resources, so a missed dispose hangs CI (macOS especially).
- Each test uses its own hardcoded port.
- `\nodoc\` on test classes.
- A new test goes in the `_test_*.pony` file for its functional area, registered in `Main.tests()` in `_test.pony`, which holds only the test runner.
- Each example has a file-level docstring saying what it demonstrates, uses the Listener/Server/Client actor structure, and uses a unique port.
