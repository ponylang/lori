use "constrained_types"
use "pony_test"

class \nodoc\ iso _TestReadBufferConstructorSize is UnitTest
  """
  Test that the constructor parameter sets the initial buffer size and minimum.
  The server verifies buffer behavior by resizing and checking invariants.
  """
  fun name(): String => "ReadBufferConstructorSize"

  fun apply(h: TestHelper) =>
    let listener = _TestReadBufferConstructorSizeListener(h)
    h.dispose_when_done(listener)
    h.long_test(5_000_000_000)

actor \nodoc\ _TestReadBufferConstructorSizeListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(h.env.root), "127.0.0.1", "7700", this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestReadBufferConstructorSizeServer =>
    _TestReadBufferConstructorSizeServer(fd, _h)

  fun ref _on_listening() =>
    // Connect a client just to trigger _on_accept
    _TestReadBufferTriggerClient(TCPConnectAuth(_h.env.root),
      "127.0.0.1", "7700")

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open listener")

actor \nodoc\ _TestReadBufferConstructorSizeServer is
  (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(fd: U32, h: TestHelper) =>
    _h = h
    // Use a custom buffer size of 512
    match MakeReadBufferSize(512)
    | let rbs: ReadBufferSize =>
      _tcp_connection = TCPConnection.server(
        TCPServerAuth(h.env.root), fd, this, this
        where read_buffer_size = rbs)
    | let _: ValidationFailure =>
      _h.fail("MakeReadBufferSize(512) should succeed")
    end

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_started() =>
    // set_read_buffer_minimum to 256 should succeed (lowering the minimum)
    match MakeReadBufferSize(256)
    | let rbs: ReadBufferSize =>
      match _tcp_connection.set_read_buffer_minimum(rbs)
      | ReadBufferResized => None
      | ReadBufferResizeBelowExpect =>
        _h.fail("set_read_buffer_minimum(256) should succeed")
      end

      // resize_read_buffer to 256 should succeed since minimum is now 256
      match _tcp_connection.resize_read_buffer(rbs)
      | ReadBufferResized => None
      | let _: ReadBufferResizeBelowExpect =>
        _h.fail("resize_read_buffer(256) should succeed")
      | let _: ReadBufferResizeBelowUsed =>
        _h.fail("resize_read_buffer(256) should succeed")
      end
    | let _: ValidationFailure =>
      _h.fail("MakeReadBufferSize(256) should succeed")
    end

    _h.complete(true)
    _tcp_connection.close()

class \nodoc\ iso _TestSetReadBufferMinimumSuccess is UnitTest
  """
  Test that set_read_buffer_minimum() succeeds and grows the buffer when
  the new minimum exceeds the current allocation.
  """
  fun name(): String => "SetReadBufferMinimumSuccess"

  fun apply(h: TestHelper) =>
    let listener = _TestSetReadBufferMinSuccessListener(h)
    h.dispose_when_done(listener)
    h.long_test(5_000_000_000)

actor \nodoc\ _TestSetReadBufferMinSuccessListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(h.env.root), "127.0.0.1", "7701", this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestSetReadBufferMinSuccessServer =>
    _TestSetReadBufferMinSuccessServer(fd, _h)

  fun ref _on_listening() =>
    _TestReadBufferTriggerClient(TCPConnectAuth(_h.env.root),
      "127.0.0.1", "7701")

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open listener")

actor \nodoc\ _TestSetReadBufferMinSuccessServer is
  (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(fd: U32, h: TestHelper) =>
    _h = h
    match MakeReadBufferSize(256)
    | let rbs: ReadBufferSize =>
      _tcp_connection = TCPConnection.server(
        TCPServerAuth(h.env.root), fd, this, this
        where read_buffer_size = rbs)
    | let _: ValidationFailure =>
      _h.fail("MakeReadBufferSize(256) should succeed")
    end

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_started() =>
    // Setting minimum to 512 should succeed and grow the buffer
    match MakeReadBufferSize(512)
    | let rbs: ReadBufferSize =>
      match _tcp_connection.set_read_buffer_minimum(rbs)
      | ReadBufferResized => None
      | ReadBufferResizeBelowExpect =>
        _h.fail("set_read_buffer_minimum(512) should succeed")
      end
    | let _: ValidationFailure =>
      _h.fail("MakeReadBufferSize(512) should succeed")
    end

    // Setting minimum back to 128 should succeed (lowering is always ok)
    match MakeReadBufferSize(128)
    | let rbs: ReadBufferSize =>
      match _tcp_connection.set_read_buffer_minimum(rbs)
      | ReadBufferResized => None
      | ReadBufferResizeBelowExpect =>
        _h.fail("set_read_buffer_minimum(128) should succeed")
      end
    | let _: ValidationFailure =>
      _h.fail("MakeReadBufferSize(128) should succeed")
    end

    _h.complete(true)
    _tcp_connection.close()

class \nodoc\ iso _TestSetReadBufferMinimumBelowExpect is UnitTest
  """
  Test that set_read_buffer_minimum() fails when the new minimum is below
  the current expect value.
  """
  fun name(): String => "SetReadBufferMinimumBelowExpect"

  fun apply(h: TestHelper) =>
    let listener = _TestSetReadBufferMinBelowExpectListener(h)
    h.dispose_when_done(listener)
    h.long_test(5_000_000_000)

actor \nodoc\ _TestSetReadBufferMinBelowExpectListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(h.env.root), "127.0.0.1", "7702", this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestSetReadBufferMinBelowExpectServer =>
    _TestSetReadBufferMinBelowExpectServer(fd, _h)

  fun ref _on_listening() =>
    _TestReadBufferTriggerClient(TCPConnectAuth(_h.env.root),
      "127.0.0.1", "7702")

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open listener")

actor \nodoc\ _TestSetReadBufferMinBelowExpectServer is
  (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(fd: U32, h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.server(
      TCPServerAuth(h.env.root), fd, this, this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_started() =>
    // Set expect to 100
    match MakeExpect(100)
    | let e: Expect => _tcp_connection.expect(e)
    end

    // Setting minimum below expect should fail
    match MakeReadBufferSize(50)
    | let rbs: ReadBufferSize =>
      match _tcp_connection.set_read_buffer_minimum(rbs)
      | ReadBufferResized =>
        _h.fail(
          "set_read_buffer_minimum(50) should fail when expect is 100")
      | ReadBufferResizeBelowExpect => None
      end
    | let _: ValidationFailure =>
      _h.fail("MakeReadBufferSize(50) should succeed")
    end

    // Setting minimum at expect should succeed
    match MakeReadBufferSize(100)
    | let rbs: ReadBufferSize =>
      match _tcp_connection.set_read_buffer_minimum(rbs)
      | ReadBufferResized => None
      | ReadBufferResizeBelowExpect =>
        _h.fail(
          "set_read_buffer_minimum(100) should succeed when expect is 100")
      end
    | let _: ValidationFailure =>
      _h.fail("MakeReadBufferSize(100) should succeed")
    end

    _h.complete(true)
    _tcp_connection.close()

class \nodoc\ iso _TestResizeReadBufferSuccess is UnitTest
  """
  Test that resize_read_buffer() succeeds for valid sizes.
  """
  fun name(): String => "ResizeReadBufferSuccess"

  fun apply(h: TestHelper) =>
    let listener = _TestResizeReadBufferSuccessListener(h)
    h.dispose_when_done(listener)
    h.long_test(5_000_000_000)

actor \nodoc\ _TestResizeReadBufferSuccessListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(h.env.root), "127.0.0.1", "7703", this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestResizeReadBufferSuccessServer =>
    _TestResizeReadBufferSuccessServer(fd, _h)

  fun ref _on_listening() =>
    _TestReadBufferTriggerClient(TCPConnectAuth(_h.env.root),
      "127.0.0.1", "7703")

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open listener")

actor \nodoc\ _TestResizeReadBufferSuccessServer is
  (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(fd: U32, h: TestHelper) =>
    _h = h
    match MakeReadBufferSize(1024)
    | let rbs: ReadBufferSize =>
      _tcp_connection = TCPConnection.server(
        TCPServerAuth(h.env.root), fd, this, this
        where read_buffer_size = rbs)
    | let _: ValidationFailure =>
      _h.fail("MakeReadBufferSize(1024) should succeed")
    end

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_started() =>
    // Resize to larger
    match MakeReadBufferSize(4096)
    | let rbs: ReadBufferSize =>
      match _tcp_connection.resize_read_buffer(rbs)
      | ReadBufferResized => None
      | let _: ReadBufferResizeBelowExpect =>
        _h.fail("resize_read_buffer(4096) should succeed")
      | let _: ReadBufferResizeBelowUsed =>
        _h.fail("resize_read_buffer(4096) should succeed")
      end
    | let _: ValidationFailure =>
      _h.fail("MakeReadBufferSize(4096) should succeed")
    end

    // Resize to smaller (also lowers minimum)
    match MakeReadBufferSize(512)
    | let rbs: ReadBufferSize =>
      match _tcp_connection.resize_read_buffer(rbs)
      | ReadBufferResized => None
      | let _: ReadBufferResizeBelowExpect =>
        _h.fail("resize_read_buffer(512) should succeed")
      | let _: ReadBufferResizeBelowUsed =>
        _h.fail("resize_read_buffer(512) should succeed")
      end
    | let _: ValidationFailure =>
      _h.fail("MakeReadBufferSize(512) should succeed")
    end

    _h.complete(true)
    _tcp_connection.close()

class \nodoc\ iso _TestResizeReadBufferBelowExpect is UnitTest
  """
  Test that resize_read_buffer() fails when the size is below the current
  expect value.
  """
  fun name(): String => "ResizeReadBufferBelowExpect"

  fun apply(h: TestHelper) =>
    let listener = _TestResizeReadBufferBelowExpectListener(h)
    h.dispose_when_done(listener)
    h.long_test(5_000_000_000)

actor \nodoc\ _TestResizeReadBufferBelowExpectListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(h.env.root), "127.0.0.1", "7704", this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestResizeReadBufferBelowExpectServer =>
    _TestResizeReadBufferBelowExpectServer(fd, _h)

  fun ref _on_listening() =>
    _TestReadBufferTriggerClient(TCPConnectAuth(_h.env.root),
      "127.0.0.1", "7704")

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open listener")

actor \nodoc\ _TestResizeReadBufferBelowExpectServer is
  (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(fd: U32, h: TestHelper) =>
    _h = h
    _tcp_connection = TCPConnection.server(
      TCPServerAuth(h.env.root), fd, this, this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_started() =>
    // Set expect to 200
    match MakeExpect(200)
    | let e: Expect => _tcp_connection.expect(e)
    end

    // Resize below expect should fail
    match MakeReadBufferSize(100)
    | let rbs: ReadBufferSize =>
      match _tcp_connection.resize_read_buffer(rbs)
      | ReadBufferResized =>
        _h.fail("resize_read_buffer(100) should fail when expect is 200")
      | let _: ReadBufferResizeBelowExpect => None
      | let _: ReadBufferResizeBelowUsed =>
        _h.fail(
          "should be ReadBufferResizeBelowExpect, not ReadBufferResizeBelowUsed"
          )
      end
    | let _: ValidationFailure =>
      _h.fail("MakeReadBufferSize(100) should succeed")
    end

    _h.complete(true)
    _tcp_connection.close()

class \nodoc\ iso _TestResizeReadBufferBelowMinLowersMin is UnitTest
  """
  Test that resize_read_buffer() below the current minimum lowers the minimum.
  Verified by subsequently setting expect to the old minimum (which would fail
  if the minimum hadn't been lowered).
  """
  fun name(): String => "ResizeReadBufferBelowMinLowersMin"

  fun apply(h: TestHelper) =>
    let listener = _TestResizeReadBufferBelowMinListener(h)
    h.dispose_when_done(listener)
    h.long_test(5_000_000_000)

actor \nodoc\ _TestResizeReadBufferBelowMinListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(h.env.root), "127.0.0.1", "7705", this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestResizeReadBufferBelowMinServer =>
    _TestResizeReadBufferBelowMinServer(fd, _h)

  fun ref _on_listening() =>
    _TestReadBufferTriggerClient(TCPConnectAuth(_h.env.root),
      "127.0.0.1", "7705")

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open listener")

actor \nodoc\ _TestResizeReadBufferBelowMinServer is
  (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(fd: U32, h: TestHelper) =>
    _h = h
    // Start with buffer size 1024 (min is also 1024)
    match MakeReadBufferSize(1024)
    | let rbs: ReadBufferSize =>
      _tcp_connection = TCPConnection.server(
        TCPServerAuth(h.env.root), fd, this, this
        where read_buffer_size = rbs)
    | let _: ValidationFailure =>
      _h.fail("MakeReadBufferSize(1024) should succeed")
    end

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_started() =>
    // Resize to 256 — this should lower the minimum from 1024 to 256
    match MakeReadBufferSize(256)
    | let rbs: ReadBufferSize =>
      match _tcp_connection.resize_read_buffer(rbs)
      | ReadBufferResized => None
      | let _: ReadBufferResizeBelowExpect =>
        _h.fail("resize_read_buffer(256) should succeed")
      | let _: ReadBufferResizeBelowUsed =>
        _h.fail("resize_read_buffer(256) should succeed")
      end
    | let _: ValidationFailure =>
      _h.fail("MakeReadBufferSize(256) should succeed")
    end

    // Now expect(512) should fail because minimum was lowered to 256
    match MakeExpect(512)
    | let e: Expect =>
      match _tcp_connection.expect(e)
      | ExpectSet =>
        _h.fail("expect(512) should fail when minimum is 256")
      | ExpectAboveBufferMinimum => None
      end
    end

    // expect(256) should succeed (at the new minimum)
    match MakeExpect(256)
    | let e: Expect =>
      match _tcp_connection.expect(e)
      | ExpectSet => None
      | ExpectAboveBufferMinimum =>
        _h.fail("expect(256) should succeed when minimum is 256")
      end
    end

    _h.complete(true)
    _tcp_connection.close()

class \nodoc\ iso _TestExpectAboveBufferMinimum is UnitTest
  """
  Test that expect() fails when the requested value exceeds the buffer minimum.
  """
  fun name(): String => "ExpectAboveBufferMinimum"

  fun apply(h: TestHelper) =>
    let listener = _TestExpectAboveBufferMinListener(h)
    h.dispose_when_done(listener)
    h.long_test(5_000_000_000)

actor \nodoc\ _TestExpectAboveBufferMinListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(h.env.root), "127.0.0.1", "7706", this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestExpectAboveBufferMinServer =>
    _TestExpectAboveBufferMinServer(fd, _h)

  fun ref _on_listening() =>
    _TestReadBufferTriggerClient(TCPConnectAuth(_h.env.root),
      "127.0.0.1", "7706")

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open listener")

actor \nodoc\ _TestExpectAboveBufferMinServer is
  (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(fd: U32, h: TestHelper) =>
    _h = h
    // Start with buffer size 128 (min is also 128)
    match MakeReadBufferSize(128)
    | let rbs: ReadBufferSize =>
      _tcp_connection = TCPConnection.server(
        TCPServerAuth(h.env.root), fd, this, this
        where read_buffer_size = rbs)
    | let _: ValidationFailure =>
      _h.fail("MakeReadBufferSize(128) should succeed")
    end

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_started() =>
    // expect(256) should fail because minimum is 128
    match MakeExpect(256)
    | let e: Expect =>
      match _tcp_connection.expect(e)
      | ExpectSet =>
        _h.fail("expect(256) should fail when minimum is 128")
      | ExpectAboveBufferMinimum => None
      end
    end

    _h.complete(true)
    _tcp_connection.close()

class \nodoc\ iso _TestExpectAtBufferMinimum is UnitTest
  """
  Test that expect() succeeds when the requested value equals the buffer
  minimum.
  """
  fun name(): String => "ExpectAtBufferMinimum"

  fun apply(h: TestHelper) =>
    let listener = _TestExpectAtBufferMinListener(h)
    h.dispose_when_done(listener)
    h.long_test(5_000_000_000)

actor \nodoc\ _TestExpectAtBufferMinListener is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h
    _tcp_listener = TCPListener(
      TCPListenAuth(h.env.root), "127.0.0.1", "7707", this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): _TestExpectAtBufferMinServer =>
    _TestExpectAtBufferMinServer(fd, _h)

  fun ref _on_listening() =>
    _TestReadBufferTriggerClient(TCPConnectAuth(_h.env.root),
      "127.0.0.1", "7707")

  fun ref _on_listen_failure() =>
    _h.fail("Unable to open listener")

actor \nodoc\ _TestExpectAtBufferMinServer is
  (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _h: TestHelper

  new create(fd: U32, h: TestHelper) =>
    _h = h
    match MakeReadBufferSize(256)
    | let rbs: ReadBufferSize =>
      _tcp_connection = TCPConnection.server(
        TCPServerAuth(h.env.root), fd, this, this
        where read_buffer_size = rbs)
    | let _: ValidationFailure =>
      _h.fail("MakeReadBufferSize(256) should succeed")
    end

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_started() =>
    // expect(256) should succeed (equals minimum)
    match MakeExpect(256)
    | let e: Expect =>
      match _tcp_connection.expect(e)
      | ExpectSet => None
      | ExpectAboveBufferMinimum =>
        _h.fail("expect(256) should succeed when minimum is 256")
      end
    end

    _h.complete(true)
    _tcp_connection.close()

actor \nodoc\ _TestReadBufferTriggerClient is
  (TCPConnectionActor & ClientLifecycleEventReceiver)
  """
  Minimal client that connects to trigger a server-side _on_accept, then
  closes. Used by read buffer tests that only need a server connection.
  """
  var _tcp_connection: TCPConnection = TCPConnection.none()

  new create(auth: TCPConnectAuth, host: String, port: String) =>
    _tcp_connection = TCPConnection.client(auth, host, port, "", this, this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_connected() =>
    _tcp_connection.close()
