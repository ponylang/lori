# Change Log

All notable changes to this project will be documented in this file. This project adheres to [Semantic Versioning](http://semver.org/) and [Keep a CHANGELOG](http://keepachangelog.com/).

## [unreleased] - unreleased

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

- Rename on_failure callback to on_connection_failure ([PR #79](https://github.com/seantallen-org/lori/pull/79))
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

