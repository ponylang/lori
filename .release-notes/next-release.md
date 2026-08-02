## Fire _on_sent in order with the other connection callbacks

`_on_sent` could arrive after callbacks for things that happened later than the send it reported: `_on_throttled` for backpressure that began after those bytes went out, `_on_received` for data that arrived once the write was done, `_on_unthrottled` for backpressure released after those bytes went out. An application reading its callbacks as a sequence of events got them out of order. The cause was dispatch: `_on_sent` went through a queued behavior message, which runs in a later turn, while those three are direct calls that run in the current one.

`_on_sent` is now a direct call, so it arrives in event order with the rest. It can no longer arrive after `_on_closed`, which the lifecycle event receivers used to document as possible.

`_on_sent` can now fire during the `send()` that queued the bytes, so anything your code updates after the call — a counter, a map, a flag — is not updated yet when `_on_sent` reads it. This is the part that compiles and misbehaves rather than failing to build, so it is worth a look at every place you track sends.

An application that sends its next message from `_on_sent` nests one `send()` inside another and recurses for as long as the sends keep draining. A peer that keeps up sets no bound on the depth, so the stack is what stops it. Send from a behavior instead.

The sends that completed in the write that hit backpressure are reported first, so `_on_sent` can now arrive just before `_on_throttled`. A `hard_close()` from one of those `_on_sent` callbacks means `_on_throttled` never fires at all: `_on_closed` has arrived and the connection is no longer throttled. A graceful `close()` leaves the queued writes to drain, so `_on_throttled` still fires.

## Deliver a send's token through _on_send_accepted

`send()` used to return `(SendToken | SendError)`. It now returns `(SendAccepted | SendError)`, and the token for an accepted send arrives at a new callback, `_on_send_accepted(token, data)`, which fires from inside `send()` before the bytes are written.

The reason is the ordering fix above. `_on_sent` is now a direct call, so it can fire during the same `send()` that queued the bytes — and the application has to be holding the token before that happens. A token returned from `send()` comes too late.

Before:

```pony
fun ref _on_connected() =>
  match \exhaustive\ _tcp_connection.send(_message)
  | let token: SendToken =>
    _outstanding.push(token)
  | let _: SendError =>
    _out.print("send refused")
  end
```

After:

```pony
fun ref _on_connected() =>
  match \exhaustive\ _tcp_connection.send(_message)
  | SendAccepted => None
  | let _: SendError =>
    _out.print("send refused")
  end

fun ref _on_send_accepted(token: SendToken, data: (ByteSeq | ByteSeqIter)) =>
  _outstanding.push(token)
```

After `_on_send_accepted`, the token still gets exactly one terminal callback — `_on_sent` when its bytes reach the OS, or `_on_send_failed` when the connection is lost or hard-closed first — and those callbacks still arrive in send order.

`data` is the same value you passed to `send()`, typed `(ByteSeq | ByteSeqIter)`. `_on_send_accepted` is a different method from the `send()` call site, so without that parameter an application that wants the payload alongside the token has to stash the payload in a field before every send.

If you declared your own `_notify_sent` behavior on your connection actor, nothing calls it now — the `TCPConnectionActor` trait no longer declares it. Nothing outside the package could ever call it, so there is no other effect.

`_on_send_failed` is unchanged: still delivered by a behavior, still arrives after `_on_closed`.

`send()` also gained a `SendResult` alias for its return type, matching `ReadBufferResizeResult` and `BufferUntilResult` elsewhere in the library.
## Fix a file descriptor being closed twice on macOS

On macOS, setting up a client connection could close one of its own file descriptors twice. The operating system can hand that descriptor number to something else in your program in between, and the second close then lands on whatever got it: an unrelated connection or file closes, and nothing reports why. A connection to a host that resolves to more than one address is the likeliest way to hit it — `localhost` is one — but a single-address connection that fails hits it too.

The same cleanup also miscounted how many connection attempts were still outstanding. That could abandon an attempt that was still running and report the connection as failed, tell `_on_connecting` that fewer attempts were in progress than really were, or leave a connection that was asked to close gracefully never sending its FIN and never finishing.

Linux and Windows were not affected. macOS can deliver two readiness notifications for a single connection attempt where they deliver one, and the second was being treated as a second attempt.

## Fix a number of SSL bugs

Fixed multiple bugs affecting SSL support, including handshake failures being reported as authentication failures, data being silently dropped on large writes and when encryption fails, and connections being closed by unrelated SSL failures elsewhere.

