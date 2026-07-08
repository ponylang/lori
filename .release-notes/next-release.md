## Deliver a completion callback for every send

`_on_sent` used to fire only when the whole write queue drained, reporting a single send. If you sent again while a previous send was still going out under backpressure (the usual move from `_on_unthrottled`), you never got `_on_sent` for the earlier sends. And if the connection dropped with sends still in flight, only the most recent one got `_on_send_failed`, so you had no way to tell how much of your data had actually left.

Now every `send()` that returns a token gets exactly one completion callback: `_on_sent` once its bytes have been handed to the OS, or `_on_send_failed` if the connection drops first. When a connection is lost mid-flight, the split tells you how far your sends got: the ones that got `_on_sent` reached the OS, the ones that got `_on_send_failed` never left. That's the accounting you need to track what's still outstanding and decide what to resend.

"Handed to the OS" means written to the kernel send buffer, not received by the peer. On a drop, bytes sitting in the kernel buffer may never reach the peer, so `_on_sent` bounds what got through rather than confirming it. End-to-end delivery is still your application's job.

