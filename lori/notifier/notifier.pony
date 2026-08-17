"""
# Notifier Package

A convenience layer over lori for straightforward TCP applications. You write
a notifier class with the callbacks you care about, hand it to an actor, and
the actor handles the rest — connection setup, calling your notifier when data
arrives or the connection state changes, and cleanup.

Lori's native API gives you full control: you build your own actor, mix in
traits, and manage a `TCPConnection` class directly. That control matters when
you need synchronous send results, custom actor structure, or multiple
connections per actor. The notifier layer trades that control for less code:
three concrete actors and three notifier traits cover the common cases without
any actor boilerplate.

## Actors and notifiers

- `ClientTCPConnection` + `ClientTCPConnectionNotify` —
  client connections
- `ServerTCPConnection` + `ServerTCPConnectionNotify` —
  server connections
- `TCPListener` + `TCPListenNotify` — listeners

The actors are concrete — only the notifiers are traits.

## Echo Server

```pony
use "lori"
use "lori/notifier"

class Echo is ServerTCPConnectionNotify
  fun ref on_received(conn: ServerTCPConnection ref, data: Array[U8] iso):
    ReadAction
  =>
    conn.write(consume data)
    KeepReading

class EchoListen is TCPListenNotify
  fun ref on_connected(listen: TCPListener ref):
    ServerTCPConnectionNotify iso^
  =>
    Echo
  fun ref on_not_listening(listen: TCPListener ref) =>
    None

actor Main
  new create(env: Env) =>
    TCPListener(TCPListenAuth(env.root), recover EchoListen end, "", "8989")
```

## Client

```pony
use "lori"
use "lori/notifier"

class MyClient is ClientTCPConnectionNotify
  fun ref on_connected(conn: ClientTCPConnection ref) =>
    conn.write("hello")
  fun ref on_connect_failed(conn: ClientTCPConnection ref,
    reason: ConnectionFailureReason)
  =>
    None

actor Main
  new create(env: Env) =>
    ClientTCPConnection(TCPConnectAuth(env.root), recover MyClient end,
      "localhost", "8989")
```

## What the notifier layer changes

**`write`/`writev` are fire-and-forget behaviors.** Lori's native `send()`
is synchronous and returns a result the caller can act on immediately. The
notifier's `write` is a behavior — it queues the data for the next turn. The
actor calls `send()` internally; use the `on_send_accepted`/`on_sent`/
`on_send_failed` callbacks to track whether each send reached the OS.

**`mute`/`unmute` are behaviors.** Lori's native `mute()` takes effect
immediately during a received callback. The notifier's `mute()` queues for
the next turn. For an immediate one-shot pause within `on_received`, return
`YieldReading`.

**SSL is a constructor parameter.** Use the `.ssl` constructor on
`ClientTCPConnection` or `TCPListener` to create an SSL-enabled connection
or listener.

## Naming

`TCPListener` exists in both `lori` and `lori/notifier`. When using both
packages, qualify the import:

```pony
use "lori"
use notifier = "lori/notifier"

// lori's class-based listener
let l1: TCPListener = ...

// notifier's actor-based listener
let l2: notifier.TCPListener = ...
```
"""
