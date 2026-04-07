# Change Log

All notable changes to this project will be documented in this file. This project adheres to [Semantic Versioning](http://semver.org/) and [Keep a CHANGELOG](http://keepachangelog.com/).

## [0.13.1] - 2026-04-07

### Fixed

- Fix connection stall after large write with backpressure ([PR #278](https://github.com/ponylang/lori/pull/278))

## [0.13.0] - 2026-03-28

### Fixed

- Fix crash when dispose() arrives before connection initialization ([PR #271](https://github.com/ponylang/lori/pull/271))

### Changed

- Use prebuilt LibreSSL binaries on Windows ([PR #263](https://github.com/ponylang/lori/pull/263))

## [0.12.0] - 2026-03-22

### Fixed

- Fix idle timer issues with SSL connections ([PR #238](https://github.com/ponylang/lori/pull/238))
- Fix resource leak from orphaned Happy Eyeballs connections ([PR #247](https://github.com/ponylang/lori/pull/247))

### Added

- Add optional connection timeout for client connections ([PR #236](https://github.com/ponylang/lori/pull/236))
- Add general-purpose one-shot timer ([PR #241](https://github.com/ponylang/lori/pull/241))

### Changed

- Expand ConnectionFailureReason with ConnectionFailedTimeout ([PR #236](https://github.com/ponylang/lori/pull/236))
- Rename expect() to buffer_until() with clearer type names ([PR #250](https://github.com/ponylang/lori/pull/250))

## [0.11.0] - 2026-03-15

### Fixed

- Fix dispose() hanging when peer FIN is missed ([PR #230](https://github.com/ponylang/lori/pull/230))

### Added

- Add configurable read buffer size ([PR #214](https://github.com/ponylang/lori/pull/214))
- Add TCP_NODELAY and socket buffer size methods ([PR #217](https://github.com/ponylang/lori/pull/217))
- Add general socket option access ([PR #221](https://github.com/ponylang/lori/pull/221))

### Changed

- Change expect() to return ExpectResult instead of raising an error ([PR #214](https://github.com/ponylang/lori/pull/214))
- Make expect() use a constrained type instead of raw USize ([PR #215](https://github.com/ponylang/lori/pull/215))

## [0.10.0] - 2026-03-03

### Fixed

- Fix accept loop spinning on persistent errors ([PR #208](https://github.com/ponylang/lori/pull/208))
- Fix read loop not yielding after byte threshold ([PR #209](https://github.com/ponylang/lori/pull/209))

### Added

- Add IPv4-only and IPv6-only support ([PR #205](https://github.com/ponylang/lori/pull/205))

### Changed

- Change TCPListener parameter order ([PR #205](https://github.com/ponylang/lori/pull/205))
- Change MaxSpawn to a constrained type ([PR #210](https://github.com/ponylang/lori/pull/210))
- Change default connection limit to 100,000 ([PR #210](https://github.com/ponylang/lori/pull/210))

## [0.9.0] - 2026-03-02

### Added

- Allow yielding during socket reads ([PR #200](https://github.com/ponylang/lori/pull/200))

### Changed

- Add structured failure reasons to connection callbacks ([PR #202](https://github.com/ponylang/lori/pull/202))

## [0.8.5] - 2026-02-20

### Fixed

- Fix wraparound error going from milli to nano in IdleTimeout ([PR #196](https://github.com/ponylang/lori/pull/196))

## [0.8.4] - 2026-02-20

### Added

- Add per-connection idle timeout ([PR #194](https://github.com/ponylang/lori/pull/194))

## [0.8.3] - 2026-02-19

### Fixed

- Fix FFI declarations for exit() and pony_os_stderr() ([PR #191](https://github.com/ponylang/lori/pull/191))

### Added

- Widen send() to accept multiple buffers via writev ([PR #190](https://github.com/ponylang/lori/pull/190))

## [0.8.2] - 2026-02-17

### Added

- Add local_address() to TCPListener ([PR #189](https://github.com/ponylang/lori/pull/189))

## [0.8.1] - 2026-02-12

### Fixed

- Fix spurious _on_connection_failure() after hard_close() ([PR #185](https://github.com/ponylang/lori/pull/185))

## [0.8.0] - 2026-02-12

### Fixed

- Fix hard_close() being a no-op during connecting phase ([PR #178](https://github.com/ponylang/lori/pull/178))
- Fix close() being a no-op during connecting phase ([PR #181](https://github.com/ponylang/lori/pull/181))

### Added

- Add first-class LibreSSL support ([PR #177](https://github.com/ponylang/lori/pull/177))

### Changed

- Drop OpenSSL 0.9.0 support ([PR #177](https://github.com/ponylang/lori/pull/177))

## [0.7.2] - 2026-02-10

### Added

- Add TLS upgrade support (STARTTLS) ([PR #171](https://github.com/ponylang/lori/pull/171))

## [0.7.1] - 2026-02-10

### Fixed

- Fix SSL host verification not disabled by set_client_verify(false) ([PR #169](https://github.com/ponylang/lori/pull/169))

## [0.7.0] - 2026-02-10

### Fixed

- Fix premature _on_unthrottled in Happy Eyeballs connect path ([PR #168](https://github.com/ponylang/lori/pull/168))

### Added

- Add send failure notification ([PR #159](https://github.com/ponylang/lori/pull/159))
- Add server start failure notification ([PR #159](https://github.com/ponylang/lori/pull/159))

### Changed

- Update ponylang/ssl dependency ([PR #147](https://github.com/ponylang/lori/pull/147))
- Remove lifecycle event receiver chaining ([PR #151](https://github.com/ponylang/lori/pull/151))
- Redesign send system for fallible sends and completion tracking ([PR #154](https://github.com/ponylang/lori/pull/154))
- Redesign SSL connection API ([PR #160](https://github.com/ponylang/lori/pull/160))

## [0.6.2] - 2025-07-16

### Changed

- Make connection limit more accurate([PR  #138](https://github.com/ponylang/lori/pull/138))
- Change SSL Dependency ([PR #146](https://github.com/ponylang/lori/pull/146))

## [0.6.1] - 2025-03-04

### Fixed

- Fix incorrect listen limit enforcement ([PR #132](https://github.com/ponylang/lori/pull/132))
- Fix memory leak ([PR #133](https://github.com/ponylang/lori/pull/133))
- Fix GC unfriendly connection limiting ([PR #134](https://github.com/ponylang/lori/pull/134))

## [0.6.0] - 2025-03-02

### Fixed

- Fix bug in TCPListener ([PR #118](https://github.com/ponylang/lori/pull/118))
- Send pending writes on client connect ([PR #126](https://github.com/ponylang/lori/pull/126))

### Added

- Add SSL support ([PR #105](https://github.com/ponylang/lori/pull/105))
- Add callback for when a server is starting up ([PR #102](https://github.com/ponylang/lori/pull/102))
- Add callback for when data is being sent ([PR #105](https://github.com/ponylang/lori/pull/105))
- Add callback for when `expect` is called ([PR #105](https://github.com/ponylang/lori/pull/105))
- Add support for setting TCP keepalive options ([PR #109](https://github.com/ponylang/lori/pull/109))
- Add ability to get local and remote names from a socket ([PR #110](https://github.com/ponylang/lori/pull/110))
- Allow setting a max connection limit ([PR #113](https://github.com/ponylang/lori/pull/113))
- Add mute and unmute functionality ([PR #117](https://github.com/ponylang/lori/pull/117))
- Implement Happy Eyeballs ([PR #125](https://github.com/ponylang/lori/pull/125))

### Changed

- An SSL library now required to build Lori ([PR #105](https://github.com/ponylang/lori/pull/105))
- Several breaking API changes introduced ([PR #105](https://github.com/ponylang/lori/pull/105))
- Several breaking API changes introduced ([PR #115](https://github.com/ponylang/lori/pull/115))
- Remove `TCPConnectionState` ([PR #121](https://github.com/ponylang/lori/pull/121))
- Make `TCPListener.state` private ([PR #121](https://github.com/ponylang/lori/pull/121))
- Make `TCPConnection.pending_writes` private ([PR #122](https://github.com/ponylang/lori/pull/122))
- Make `TCPListenerActor.on_closed` private ([PR #123](https://github.com/ponylang/lori/pull/123))

## [0.5.1] - 2025-02-13

### Fixed

- Fix a Server Shutdown Race Condition ([PR #101](https://github.com/ponylang/lori/pull/101))
- Fix a "Data Never Seen on Server Start" Race Condition ([PR #101](https://github.com/ponylang/lori/pull/101))

## [0.5.0] - 2022-11-02

### Added

- Add Windows Support ([PR #82](https://github.com/seantallen-org/lori/pull/82))

### Changed

- `TCPListenerActor.on_accept` signature ([PR #82](https://github.com/seantallen-org/lori/pull/82))

## [0.4.0] - 2022-10-04

### Changed

- Rename on_failure callback to _on_connection_failure ([PR #79](https://github.com/seantallen-org/lori/pull/79))
- Make lori callbacks private ([PR #80](https://github.com/seantallen-org/lori/pull/80))

## [0.3.0] - 2022-09-28

### Changed

- Update object capabilities to match Pony standard library pattern ([PR #76](https://github.com/seantallen-org/lori/pull/76))

## [0.2.2] - 2022-09-14

### Added

- Add basic "outgoing failed logic" ([PR #75](https://github.com/seantallen-org/lori/pull/75))

## [0.2.1] - 2022-02-26

### Fixed

- Update to work with Pony 0.49.0 ([PR #74](https://github.com/seantallen-org/lori/pull/74))

## [0.2.0] - 2022-02-02

### Changed

- Update interfaces with private methods work with Pony 0.47.0 ([PR #71](https://github.com/seantallen-org/lori/pull/71))

## [0.1.1] - 2022-01-16

### Fixed

- Update to work with Pony 0.46.0 ([PR #70](https://github.com/seantallen-org/lori/pull/70))

## [0.1.0] - 2021-05-07

### Fixed

- Fix loss of incoming connections ([PR #63](https://github.com/seantallen-org/lori/pull/63))

### Changed

- Change license to BSD ([PR #62](https://github.com/seantallen-org/lori/pull/62))

## [0.0.1] - 2020-09-18

### Added

- Initial release

