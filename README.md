# Lori

Pony TCP classes reimagined.

## Status

Lori is beta quality software that will change frequently. Expect breaking changes. That said, you should feel comfortable using it in your projects.

Please note that if this library encounters a state that the programmers thought was impossible to hit, it will exit the program immediately with informational messages. Normal errors are handled in standard Pony fashion.

## Installation

* Install [corral](https://github.com/ponylang/corral)
* `corral add github.com/ponylang/lori.git --version 0.6.0`
* `corral fetch` to fetch your dependencies
* `use "lori"` to include this package
* `corral run -- ponyc` to compile your application

Note: The net_ssl transitive dependency requires a C SSL library to be installed. Please see the net_ssl installation instructions for more information.

## API Documentation

[https://ponylang.github.io/lori/](https://ponylang.github.io/lori/)
