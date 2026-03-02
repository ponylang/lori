## Allow yielding during socket reads

Under sustained inbound traffic, a single connection's read loop can monopolize the Pony scheduler. `yield_read()` lets the application exit the read loop cooperatively, giving other actors a chance to run. Reading resumes automatically in the next scheduler turn.

Call `yield_read()` from within `_on_received()` to implement any yield policy — message count, byte threshold, time-based, etc.:

```pony
fun ref _on_received(data: Array[U8] iso) =>
  _received_count = _received_count + 1

  // Yield every 10 messages to let other actors run
  if (_received_count % 10) == 0 then
    _tcp_connection.yield_read()
  end
```

Unlike `mute()`/`unmute()`, which persistently stop reading until reversed, `yield_read()` is a one-shot pause — the read loop resumes on its own without explicit action. The library does not impose any built-in yield policy; the application decides when to yield.

## Add structured failure reasons to connection callbacks

The failure callbacks `_on_connection_failure`, `_on_start_failure`, and `_on_tls_failure` now carry a reason parameter that identifies why the failure occurred. This is a breaking change — all implementations of these callbacks must be updated to accept the new parameter.

### Before

```pony
fun ref _on_connection_failure() =>
  // No way to know what went wrong
  None

fun ref _on_start_failure() =>
  None

fun ref _on_tls_failure() =>
  None
```

### After

```pony
fun ref _on_connection_failure(reason: ConnectionFailureReason) =>
  match reason
  | ConnectionFailedDNS => // Name resolution failed
  | ConnectionFailedTCP => // All TCP attempts failed
  | ConnectionFailedSSL => // SSL handshake failed
  end

fun ref _on_start_failure(reason: StartFailureReason) =>
  match reason
  | StartFailedSSL => // SSL session or handshake failed
  end

fun ref _on_tls_failure(reason: TLSFailureReason) =>
  match reason
  | TLSAuthFailed => // Certificate/auth error
  | TLSGeneralError => // Protocol error
  end
```

The reason types are union type aliases of primitives, following the same pattern as `StartTLSError` and `SendError`. Applications that don't need the reason can add the parameter and ignore it.

