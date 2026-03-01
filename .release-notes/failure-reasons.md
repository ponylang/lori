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
