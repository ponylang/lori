interface LegacyTCPListenNotify
  """
  Notifications for a `LegacyTCPListener`.

  This mirrors the standard library `net` package's `TCPListenNotify` interface
  so that code written against the old API can move to lori with small changes.
  The parameter types are `LegacyTCPListener` and `LegacyTCPConnectionNotify`
  where the stdlib used `TCPListener` and `TCPConnectionNotify`.

  For an example of use, see the documentation for `LegacyTCPListener`.
  """
  fun ref listening(listen: LegacyTCPListener ref) =>
    """
    Called when the listener has been bound to an address.
    """
    None

  fun ref not_listening(listen: LegacyTCPListener ref)
    """
    Called if the listener could not be bound to an address.

    You must implement error handling. To ignore the failure, provide an empty
    body:

    ```pony
    fun ref not_listening(listen: LegacyTCPListener ref) =>
      None
    ```
    """

  fun ref closed(listen: LegacyTCPListener ref) =>
    """
    Called when the listener is closed.
    """
    None

  fun ref connected(listen: LegacyTCPListener ref)
    : LegacyTCPConnectionNotify iso^ ?
    """
    Create a `LegacyTCPConnectionNotify` for a newly accepted connection. Raise
    an error to reject the connection.
    """
