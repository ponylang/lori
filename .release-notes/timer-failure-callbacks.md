## Add timer ASIO subscription failure callbacks

Previously, when the idle timer or a user timer's ASIO event subscription failed (e.g. `ENOMEM` from the kernel's `kevent` or `epoll_ctl`), lori would silently cancel the timer with no notification. The connection would keep running without the protection the application had configured. There was no way for the application to know the timer subsystem had failed or to retry.

Two new lifecycle callbacks now surface these failures.

`_on_idle_timer_failure()` fires when the idle timer's ASIO subscription fails. Before the callback runs, the idle timer has been cancelled and its duration cleared. The connection continues to run — the application decides whether to re-arm via `idle_timeout(duration)`, close the connection, or take some other action.

`_on_timer_failure()` fires when a user timer's ASIO subscription fails. Before the callback runs, the user timer has been cancelled and the token cleared. As with the idle failure callback, the application decides how to recover — call `set_timer(duration)` to create a new timer, close the connection, etc.

Both callbacks have default no-op implementations, so applications that don't override them keep the current silent-cancel behavior.

```pony
actor MyConnection is (TCPConnectionActor & ClientLifecycleEventReceiver)
  // ...

  fun ref _on_idle_timer_failure() =>
    // Idle detection is off. Try to bring it back up.
    match MakeIdleTimeout(30_000)
    | let t: IdleTimeout => _tcp_connection.idle_timeout(t)
    end

  fun ref _on_timer_failure() =>
    // The query timer never armed. Give up on this request.
    _tcp_connection.close()
```

Connect timers are unaffected — their ASIO subscription failures already route to `_on_connection_failure(ConnectionFailedTimerError)`.
