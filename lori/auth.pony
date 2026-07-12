primitive NetAuth
  """
  Authority to use the network. Made from `AmbientAuth`. The root of lori's
  network authority hierarchy; the TCP authorities below are made from it.
  """
  new create(from: AmbientAuth) =>
    None

primitive TCPAuth
  """
  Authority to use TCP. Made from `AmbientAuth` or `NetAuth`.
  """
  new create(from: (AmbientAuth | NetAuth)) =>
    None

primitive TCPListenAuth
  """
  Authority to open a TCP listener. Made from `AmbientAuth`, `NetAuth`, or
  `TCPAuth`. Passed to `TCPListener`.
  """
  new create(from: (AmbientAuth | NetAuth | TCPAuth)) =>
    None

primitive TCPConnectAuth
  """
  Authority to open an outbound TCP connection. Made from `AmbientAuth`,
  `NetAuth`, or `TCPAuth`. Passed to the `TCPConnection` client constructors.
  """
  new create(from: (AmbientAuth | NetAuth | TCPAuth)) =>
    None

primitive TCPServerAuth
  """
  Authority to run the server side of an accepted TCP connection. Made from
  `AmbientAuth`, `NetAuth`, `TCPAuth`, or `TCPListenAuth`. Passed to the
  `TCPConnection` server constructors.
  """
  new create(from: (AmbientAuth | NetAuth | TCPAuth | TCPListenAuth)) =>
    None
