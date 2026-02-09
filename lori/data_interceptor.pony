interface WireSender
  """
  Sends data directly to the wire, bypassing the outgoing interceptor
  pipeline. Provided by TCPConnection to interceptors.
  """
  fun ref send(data: ByteSeq)

interface IncomingDataReceiver
  """
  Receives processed incoming data from an interceptor. TCPConnection
  provides an implementation that delivers data to the lifecycle event
  receiver's _on_received callback.
  """
  fun ref receive(data: Array[U8] iso)

interface InterceptorControl
  """
  Provided by TCPConnection to interceptors during on_setup(). Gives the
  interceptor the ability to signal readiness, send wire data during
  handshake, and close the connection on protocol errors.

  Only on_setup receives this interface. incoming/outgoing receive the
  narrower WireSender, so interceptors cannot accidentally signal readiness
  or close the connection from data processing methods.

  Interceptors that need to close the connection on errors during incoming
  processing (e.g., SSL encountering an error mid-stream) should store this
  reference from on_setup() and call close() on it.
  """
  fun ref signal_ready()
  fun ref send_to_wire(data: ByteSeq)
  fun ref close()

trait DataInterceptor
  """
  Protocol-level data transformer. Sits between TCP and the application.
  Handles concerns like encryption, compression, or framing.

  Both incoming and outgoing use a push model: the interceptor receives
  data and pushes results downstream. This supports protocols like SSL
  that may produce zero, one, or many output chunks per input chunk.
  """

  fun ref on_setup(control: InterceptorControl ref) =>
    """
    Called when the TCP connection is established, before the application
    is notified. Use this for protocol handshakes.

    Call control.signal_ready() when the protocol is ready for application
    data. Non-handshake interceptors should signal immediately (the
    default). Use control.send_to_wire() for protocol data (e.g.,
    ClientHello). Use control.close() on fatal protocol errors.

    TCPConnection defers _on_connected/_on_started until signal_ready()
    is called. Incoming data continues to flow through the interceptor
    during this time (for handshake processing). TCP reads begin
    immediately after on_setup returns, regardless of whether
    signal_ready has been called.
    """
    control.signal_ready()

  fun ref on_teardown() =>
    """
    Called when the connection is closing, for protocol cleanup (e.g.,
    SSL session disposal). Called regardless of whether signal_ready()
    was ever called — handles the case where the connection closes during
    handshake.
    """
    None

  fun ref incoming(data: Array[U8] iso,
    receiver: IncomingDataReceiver ref,
    wire: WireSender ref)
  =>
    """
    Process incoming data from the wire. Call receiver.receive() for each
    chunk of processed data to deliver to the application.

    The wire parameter is for protocols that need to send data during
    receive processing (e.g., SSL handshake responses, renegotiation).
    """
    receiver.receive(consume data)

  fun ref outgoing(data: ByteSeq, wire: WireSender ref) =>
    """
    Process outgoing data from the application. Call wire.send() for each
    chunk of processed data to send to the wire.

    The push model supports protocols like SSL where a single plaintext
    write may produce multiple encrypted records, or where data is
    buffered during handshake and flushed later.
    """
    wire.send(data)

  fun ref adjust_expect(qty: USize): USize =>
    """
    Adjust the expect quantity for protocols that change data framing.

    Called when the application sets an expect value. The interceptor
    receives the application's requested chunk size, may store it
    internally, and returns the value that TCPConnection should use for
    TCP reads.

    SSL returns 0 (read all available) and tracks the application's value
    internally for its own framing when delivering decrypted data.
    """
    qty
