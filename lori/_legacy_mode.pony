use "pony_test"

interface val _LegacyMode
  """
  A test scenario for the Legacy API integration tests: builds the client to
  connect and the server-side notifier for the accepted connection. Each
  integration test is one mode. Used only by `_test_legacy.pony`.
  """
  fun make_client(h: TestHelper, port: String): LegacyTCPClient
  fun make_server(h: TestHelper): LegacyTCPConnectionNotify iso^
