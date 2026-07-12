trait ServerLifecycleEventReceiver
  """
  Application-level callbacks for server-side TCP connections.
  One receiver per connection, no chaining.
  """
  fun ref _connection(): TCPConnection

  fun ref _on_started() =>
    """
    Called when a server connection is ready for application data.
    """
    None

  fun ref _on_closed() =>
    """
    Called when the connection is closed.
    """
    None

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    """
    Called each time data is received on this connection.

    Return `KeepReading` to let the read loop take the next message, or
    `YieldReading` to stop after this one and give other actors a turn.
    """
    KeepReading

  fun ref _on_throttled() =>
    """
    Called when we start experiencing backpressure.

    This can run inside a `send()` that has not returned yet: `send()` writes to
    the socket, and a partial write applies backpressure right there. Closing
    the connection from here is supported. When this runs inside a `send()`,
    that send is still accepted, and its token still gets `_on_sent` or
    `_on_send_failed`.
    """
    None

  fun ref _on_unthrottled() =>
    """
    Called when backpressure is released.
    """
    None

  fun ref _on_sent(token: SendToken) =>
    """
    Called when the bytes from a successful `send()` have been handed to the
    OS: written to the kernel send buffer, not necessarily received by the
    peer. The token matches the one returned by that `send()` call, and this
    callback fires exactly once for it.

    Always fires in a subsequent behavior turn, never synchronously during
    `send()`, so the caller has the `SendToken` return value before the
    callback arrives. Callbacks arrive in send order. If a send's bytes reach
    the OS just as the connection closes, its `_on_sent` can arrive after
    `_on_closed`.
    """
    None

  fun ref _on_send_failed(token: SendToken) =>
    """
    Called when the bytes from a successful `send()` could not be handed to
    the OS because the connection was lost or hard-closed first. The token
    matches the one returned by that `send()` call, and this callback fires
    exactly once for it. A graceful `close()` sends what's still queued, so only
    a hard close or a lost connection fires this. On a hard close, the sends
    that reached the OS fire `_on_sent` and the rest fire this, so the split
    shows how far your data got.

    Always fires in a subsequent behavior turn, never synchronously during
    `hard_close()`. Always arrives after `_on_closed`, which fires
    synchronously during `hard_close()`.
    """
    None

  fun ref _on_start_failure(reason: StartFailureReason) =>
    """
    Called when a server connection fails to start. This covers failures
    that occur before _on_started would have fired, such as an SSL
    handshake failure. The application was never notified of the connection
    via _on_started.

    The `reason` parameter identifies the cause of the failure. Currently
    the only reason is `StartFailedSSL` (SSL session creation or handshake
    failure).
    """
    None

  fun ref _on_tls_ready() =>
    """
    Called when a TLS handshake initiated by `start_tls()` completes
    successfully. The connection is now encrypted and ready for
    application data over TLS.
    """
    None

  fun ref _on_tls_failure(reason: TLSFailureReason) =>
    """
    Called when a TLS handshake initiated by `start_tls()` fails. Fires
    synchronously during `hard_close()`, immediately before `_on_closed()`.
    The connection was already established (the application received
    `_on_started` earlier), so `_on_closed` always follows to signal
    connection teardown.

    The `reason` parameter distinguishes authentication failures
    (`TLSAuthFailed`) from other protocol errors (`TLSGeneralError`).
    """
    None

  fun ref _on_idle_timeout() =>
    """
    Called when no successful send or receive has occurred for the duration
    configured by `idle_timeout()`. This measures application-level inactivity,
    not wire-level: pending OS write buffer drains and failed sends
    (`SendErrorNotWriteable`) do not count as activity.

    The timer re-arms after each firing while the connection is open, so it
    keeps reporting an idle connection until the application acts. Call
    `idle_timeout(None)` to disable it; `hard_close()` cancels it.

    A graceful `close()` does not cancel it. The firing itself does not re-arm
    the timer once a close has begun, but I/O on the closing connection still
    resets it, so this callback can arrive again on a connection that is closing
    and still moving bytes.

    The application decides what action to take — close the connection, send a
    keepalive, log a warning, etc.

    If the idle timer's ASIO event subscription fails,
    `_on_idle_timer_failure()` is delivered instead of this callback.
    """
    None

  fun ref _on_idle_timer_failure() =>
    """
    Called when the idle timer's ASIO event subscription fails. This is
    typically caused by the kernel returning an error (e.g. `ENOMEM`) from
    `kevent` or `epoll_ctl` when the runtime tries to register the timer.

    Before this callback fires, the idle timer has already been cancelled:
    the ASIO event is unsubscribed and the configured timeout duration is
    cleared. Idle timeout detection is no longer active on this connection.

    The connection itself is unaffected and continues running. The
    application decides how to recover — for example, call
    `idle_timeout(duration)` from within this callback to re-arm, or
    `close()` the connection. A re-armed timer can itself fail
    asynchronously under sustained pressure; if the new subscription also
    errors, this callback fires again.
    """
    None

  fun ref _on_timer(token: TimerToken) =>
    """
    Called when a one-shot timer created by `set_timer()` fires. The token
    matches the one returned by `set_timer()`.

    Fires once per `set_timer()` call. The timer is consumed before the
    callback, so it is safe to call `set_timer()` from within `_on_timer()`
    to re-arm. No automatic re-arming occurs.

    If the user timer's ASIO event subscription fails, `_on_timer_failure()`
    is delivered instead of this callback.
    """
    None

  fun ref _on_timer_failure() =>
    """
    Called when the user timer's ASIO event subscription fails. This is
    typically caused by the kernel returning an error (e.g. `ENOMEM`) from
    `kevent` or `epoll_ctl` when the runtime tries to register the timer.

    User timers have two error paths:

    - Synchronous: `set_timer()` returns a `SetTimerError`
      (`SetTimerNotOpen` or `SetTimerAlreadyActive`) when preconditions
      prevent the timer from being created at all.
    - Asynchronous: this callback fires when `set_timer()` succeeded but
      the ASIO event subscription later failed.

    Before this callback fires, the user timer has already been cancelled:
    the ASIO event is unsubscribed and the timer token is cleared. The
    token that the application was waiting on is no longer valid.

    The connection itself is unaffected and continues running. The
    application decides how to recover — for example, call
    `set_timer(duration)` from within this callback to create a new timer,
    or `close()` the connection. A new timer can itself fail
    asynchronously under sustained pressure; if the new subscription also
    errors, this callback fires again.
    """
    None

trait ClientLifecycleEventReceiver
  """
  Application-level callbacks for client-side TCP connections.
  One receiver per connection, no chaining.
  """
  fun ref _connection(): TCPConnection

  fun ref _on_connecting(inflight_connections: U32) =>
    """
    Called if name resolution succeeded for a TCPConnection and we are now
    waiting for a connection to the server to succeed. The count is the number
    of connections we're trying. This callback will be called each time the
    count changes, until a connection is made or _on_connection_failure is
    called.
    """
    None

  fun ref _on_connected() =>
    """
    Called when a connection is ready for application data.
    """
    None

  fun ref _on_connection_failure(reason: ConnectionFailureReason) =>
    """
    Called when a connection fails to open. For SSL connections, this is
    also called when the SSL handshake fails before _on_connected would
    have been delivered, since the application was never notified of the
    connection.

    The `reason` parameter identifies the failure stage:
    `ConnectionFailedDNS` (name resolution failed), `ConnectionFailedTCP`
    (resolved but all TCP attempts failed), `ConnectionFailedSSL`
    (TCP connected but SSL handshake failed), `ConnectionFailedTimeout`
    (the connection attempt timed out before completing), or
    `ConnectionFailedTimerError` (the connect timer's ASIO event
    subscription failed).
    """
    None

  fun ref _on_closed() =>
    """
    Called when the connection is closed.
    """
    None

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    """
    Called each time data is received on this connection.

    Return `KeepReading` to let the read loop take the next message, or
    `YieldReading` to stop after this one and give other actors a turn.
    """
    KeepReading

  fun ref _on_throttled() =>
    """
    Called when we start experiencing backpressure.

    This can run inside a `send()` that has not returned yet: `send()` writes to
    the socket, and a partial write applies backpressure right there. Closing
    the connection from here is supported. When this runs inside a `send()`,
    that send is still accepted, and its token still gets `_on_sent` or
    `_on_send_failed`.
    """
    None

  fun ref _on_unthrottled() =>
    """
    Called when backpressure is released.
    """
    None

  fun ref _on_sent(token: SendToken) =>
    """
    Called when the bytes from a successful `send()` have been handed to the
    OS: written to the kernel send buffer, not necessarily received by the
    peer. The token matches the one returned by that `send()` call, and this
    callback fires exactly once for it.

    Always fires in a subsequent behavior turn, never synchronously during
    `send()`, so the caller has the `SendToken` return value before the
    callback arrives. Callbacks arrive in send order. If a send's bytes reach
    the OS just as the connection closes, its `_on_sent` can arrive after
    `_on_closed`.
    """
    None

  fun ref _on_send_failed(token: SendToken) =>
    """
    Called when the bytes from a successful `send()` could not be handed to
    the OS because the connection was lost or hard-closed first. The token
    matches the one returned by that `send()` call, and this callback fires
    exactly once for it. A graceful `close()` sends what's still queued, so only
    a hard close or a lost connection fires this. On a hard close, the sends
    that reached the OS fire `_on_sent` and the rest fire this, so the split
    shows how far your data got.

    Always fires in a subsequent behavior turn, never synchronously during
    `hard_close()`. Always arrives after `_on_closed`, which fires
    synchronously during `hard_close()`.
    """
    None

  fun ref _on_tls_ready() =>
    """
    Called when a TLS handshake initiated by `start_tls()` completes
    successfully. The connection is now encrypted and ready for
    application data over TLS.
    """
    None

  fun ref _on_tls_failure(reason: TLSFailureReason) =>
    """
    Called when a TLS handshake initiated by `start_tls()` fails. Fires
    synchronously during `hard_close()`, immediately before `_on_closed()`.
    The connection was already established (the application received
    `_on_connected` earlier), so `_on_closed` always follows to signal
    connection teardown.

    The `reason` parameter distinguishes authentication failures
    (`TLSAuthFailed`) from other protocol errors (`TLSGeneralError`).
    """
    None

  fun ref _on_idle_timeout() =>
    """
    Called when no successful send or receive has occurred for the duration
    configured by `idle_timeout()`. This measures application-level inactivity,
    not wire-level: pending OS write buffer drains and failed sends
    (`SendErrorNotWriteable`) do not count as activity.

    The timer re-arms after each firing while the connection is open, so it
    keeps reporting an idle connection until the application acts. Call
    `idle_timeout(None)` to disable it; `hard_close()` cancels it.

    A graceful `close()` does not cancel it. The firing itself does not re-arm
    the timer once a close has begun, but I/O on the closing connection still
    resets it, so this callback can arrive again on a connection that is closing
    and still moving bytes.

    The application decides what action to take — close the connection, send a
    keepalive, log a warning, etc.

    If the idle timer's ASIO event subscription fails,
    `_on_idle_timer_failure()` is delivered instead of this callback.
    """
    None

  fun ref _on_idle_timer_failure() =>
    """
    Called when the idle timer's ASIO event subscription fails. This is
    typically caused by the kernel returning an error (e.g. `ENOMEM`) from
    `kevent` or `epoll_ctl` when the runtime tries to register the timer.

    Before this callback fires, the idle timer has already been cancelled:
    the ASIO event is unsubscribed and the configured timeout duration is
    cleared. Idle timeout detection is no longer active on this connection.

    The connection itself is unaffected and continues running. The
    application decides how to recover — for example, call
    `idle_timeout(duration)` from within this callback to re-arm, or
    `close()` the connection. A re-armed timer can itself fail
    asynchronously under sustained pressure; if the new subscription also
    errors, this callback fires again.
    """
    None

  fun ref _on_timer(token: TimerToken) =>
    """
    Called when a one-shot timer created by `set_timer()` fires. The token
    matches the one returned by `set_timer()`.

    Fires once per `set_timer()` call. The timer is consumed before the
    callback, so it is safe to call `set_timer()` from within `_on_timer()`
    to re-arm. No automatic re-arming occurs.

    If the user timer's ASIO event subscription fails, `_on_timer_failure()`
    is delivered instead of this callback.
    """
    None

  fun ref _on_timer_failure() =>
    """
    Called when the user timer's ASIO event subscription fails. This is
    typically caused by the kernel returning an error (e.g. `ENOMEM`) from
    `kevent` or `epoll_ctl` when the runtime tries to register the timer.

    User timers have two error paths:

    - Synchronous: `set_timer()` returns a `SetTimerError`
      (`SetTimerNotOpen` or `SetTimerAlreadyActive`) when preconditions
      prevent the timer from being created at all.
    - Asynchronous: this callback fires when `set_timer()` succeeded but
      the ASIO event subscription later failed.

    Before this callback fires, the user timer has already been cancelled:
    the ASIO event is unsubscribed and the timer token is cleared. The
    token that the application was waiting on is no longer valid.

    The connection itself is unaffected and continues running. The
    application decides how to recover — for example, call
    `set_timer(duration)` from within this callback to create a new timer,
    or `close()` the connection. A new timer can itself fail
    asynchronously under sustained pressure; if the new subscription also
    errors, this callback fires again.
    """
    None

type EitherLifecycleEventReceiver is
  (ServerLifecycleEventReceiver | ClientLifecycleEventReceiver)
