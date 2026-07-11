## Deliver a completion callback for every send

`_on_sent` used to fire only when the whole write queue drained, reporting a single send. If you sent again while a previous send was still going out under backpressure (the usual move from `_on_unthrottled`), you never got `_on_sent` for the earlier sends. And if the connection dropped with sends still in flight, only the most recent one got `_on_send_failed`, so you had no way to tell how much of your data had actually left.

Now every `send()` that returns a token gets exactly one completion callback: `_on_sent` once its bytes have been handed to the OS, or `_on_send_failed` if the connection drops first. When a connection is lost mid-flight, the split tells you how far your sends got: the ones that got `_on_sent` reached the OS, the ones that got `_on_send_failed` never left. That's the accounting you need to track what's still outstanding and decide what to resend.

"Handed to the OS" means written to the kernel send buffer, not received by the peer. On a drop, bytes sitting in the kernel buffer may never reach the peer, so `_on_sent` bounds what got through rather than confirming it. End-to-end delivery is still your application's job.

## Fix a hang when closing a connection while handling received data

Closing a connection from inside `_on_received` — for example, closing once you've read a full message — could leave the connection attempting one more read on the socket it had just closed. Under connection churn (many connections opening and closing), that stray read could block one of the runtime's scheduler threads and keep the program from exiting.

Closing a connection while handling received data no longer triggers this hang.

## Fix connection hang under sustained write backpressure

A connection could permanently stop making progress under sustained write backpressure while its peer was still sending — data stopped flowing in both directions and the connection never recovered on its own, staying wedged until it was closed. This affected echo, relay, and proxy-style connections that pause reading with `mute()` while a write is backed up, and was most likely to appear on multi-threaded runtimes. Such a connection now recovers and continues once the backpressure clears.

## Fix a crash when hard closing an SSL connection from a callback

Calling `hard_close()` on an SSL connection from inside one of its own lifecycle callbacks — `_on_received`, `_on_connected`, `_on_started`, or `_on_tls_ready` — crashed the process. Dropping a connection the moment its handshake finished, or closing one as soon as you read a message you won't serve, was enough to trigger it.

Hard closing an SSL connection from any of those callbacks now shuts it down cleanly. Any decrypted messages still undelivered from the same read are dropped, which is what closing the connection asked for. Graceful `close()` was never affected, and neither were plaintext connections.

## Fix mute() not stopping data delivery on SSL connections

Calling `mute()` from `_on_received` stops a plaintext connection delivering data right there. An SSL connection kept going: every remaining decrypted message from the same read arrived anyway. An application that mutes because it can't keep up got handed more data regardless.

`mute()` now stops delivery on an SSL connection as soon as the application calls it. Messages already decrypted but not yet delivered are held, not dropped, and `unmute()` delivers them before anything read off the socket afterward. Closing a muted connection still drops them, as it always has for a muted plaintext connection.

## Fix a yield from _on_received not taking effect on SSL connections until every waiting message was delivered

Returning `YieldReading` from `_on_received` stops the connection reading until the next scheduler turn, so other actors get one. (See the API change below; before this release you called `yield_read()` for the same thing.)

On an SSL connection the yield did not stop reading. Messages that had arrived together were all delivered first, so an application yielding after every single message could still be handed a hundred of them before anything else ran. Under load that is the stall yielding exists to prevent, and there was no way around it.

The yield now takes effect after the message that returned it, on SSL connections as on plaintext ones.

## _on_received now returns what the read loop should do next

`yield_read()` is gone. `_on_received` returns a `ReadAction`: return `YieldReading` to stop the read loop after this message and give other actors a turn, or `KeepReading` to take the next one.

```pony
// Before
fun ref _on_received(data: Array[U8] iso) =>
  _handled = _handled + 1
  if (_handled % 10) == 0 then
    _tcp_connection.yield_read()
  end

// After
fun ref _on_received(data: Array[U8] iso): ReadAction =>
  _handled = _handled + 1
  if (_handled % 10) == 0 then
    return YieldReading
  end
  KeepReading
```

Every `_on_received` has to return one of the two. `KeepReading` is what the trait returns by default, so a receiver that does not override `_on_received` needs no change.

## Add OpenSSL 4.0.x support

Lori can now be built against OpenSSL 4.0.x. Select it at compile time with `-Dopenssl_4.0.x`, or pass `ssl=4.0.x` to `make` when building Lori itself.

## Update ssl dependency to 3.0.0

Lori now requires ssl 3.0.0. Building an `SSLContext` and passing it to `ssl_client`, `ssl_server`, or `start_tls` works as before. If your own code calls other parts of the ssl package directly, see the ssl 3.0.0 release notes for its API changes.
## Fix graceful close dropping writes queued under backpressure

When a connection was under write backpressure — bytes you sent were queued because the socket couldn't take them yet — a graceful `close()` dropped those queued bytes. They never reached the peer, and their sends completed with `_on_send_failed` instead of `_on_sent`, even though you closed the connection cleanly rather than aborting it.

A graceful `close()` now sends what is still queued before shutting the connection down, so the data you handed to an accepted `send()` goes out rather than being dropped, and those sends fire `_on_sent`. `hard_close()` is unchanged: it still drops queued writes and fails their sends with `_on_send_failed`.

