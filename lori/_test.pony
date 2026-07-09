use "pony_test"

actor \nodoc\ Main is TestList
  new create(env: Env) =>
    PonyTest(env, this)

  new make() =>
    None

  fun tag tests(test: PonyTest) =>
    test(_TestCanListen)
    test(_TestListenerLocalAddress)
    test(_TestMute)
    test(_TestOutgoingFails)
    test(_TestPingPong)
    test(_TestSSLPingPong)
    test(_TestBasicBufferUntil)
    test(_TestUnmute)
    test(_TestSendToken)
    test(_TestSendAfterClose)
    test(_TestHardCloseDuringReceive)
    test(_TestHardCloseAfterFramedReceive)
    test(_TestSSLHardCloseDuringReceive)
    test(_TestSSLCloseDuringReceive)
    test(_TestSSLHardCloseOnConnected)
    test(_TestSSLHardCloseOnStarted)
    test(_TestStartTLSHardCloseOnTLSReady)
    test(_TestStartTLSPingPong)
    test(_TestStartTLSPreconditions)
    test(_TestHardCloseWhileConnecting)
    test(_TestCloseWhileConnecting)
    test(_TestSendv)
    test(_TestSendvEmpty)
    test(_TestSendvMixedEmpty)
    test(_TestSSLSendv)
    test(_TestSendSSLLargeSingleSend)
    test(_TestIdleTimeout)
    test(_TestIdleTimeoutReset)
    test(_TestIdleTimeoutDisable)
    test(_TestSSLIdleTimeout)
    test(_TestSSLIdleTimeoutNotArmedDuringHandshake)
    test(_TestSSLIdleTimeoutDeferredArm)
    test(_TestYieldRead)
    test(_TestIP4PingPong)
    test(_TestIP6PingPong)
    test(_TestMaxSpawnRejectsZero)
    test(_TestMaxSpawnAcceptsBoundary)
    test(_TestDefaultMaxSpawn)
    test(_TestReadBufferSizeRejectsZero)
    test(_TestReadBufferSizeAcceptsBoundary)
    test(_TestDefaultReadBufferSize)
    test(_TestReadBufferConstructorSize)
    test(_TestSetReadBufferMinimumSuccess)
    test(_TestSetReadBufferMinimumBelowBufferSize)
    test(_TestResizeReadBufferSuccess)
    test(_TestResizeReadBufferBelowBufferSize)
    test(_TestResizeReadBufferBelowMinLowersMin)
    test(_TestBufferSizeAboveMinimum)
    test(_TestBufferSizeAtMinimum)
    test(_TestSocketOptionsConnected)
    test(_TestSocketOptionsNotConnected)
    test(_TestConnectionTimeoutFires)
    test(_TestConnectionTimeoutCancelledOnConnect)
    test(_TestSSLConnectionTimeoutFires)
    test(_TestSSLConnectionTimeoutCancelledOnConnect)
    test(_TestConnectionTimeoutValidationRejectsZero)
    test(_TestConnectionTimeoutValidationAcceptsBoundary)
    test(_TestCloseWhileConnectingWithTimeout)
    test(_TestHardCloseWhileConnectingWithTimeout)
    test(_TestTimerFires)
    test(_TestTimerCancel)
    test(_TestTimerNotResetByIO)
    test(_TestSetTimerNotOpen)
    test(_TestSetTimerAlreadyActive)
    test(_TestTimerRearmFromCallback)
    test(_TestTimerCancelWrongToken)
    test(_TestTimerHardCloseCleanup)
    test(_TestTimerSetDuringClosing)
    test(_TestTimerDurationValidationRejectsZero)
    test(_TestTimerDurationValidationAcceptsBoundary)
    test(_TestTimerSurvivesClose)
    test(_TestSetTimerNotOpenDuringSSLHandshake)
    test(_TestSetTimerNotOpenDuringSSLHandshakeServer)
    test(_TestSSLHandshakeFailureClient)
    test(_TestSSLHandshakeFailureServer)
    test(_TestSSLHandshakeCompleteTransitionsToOpen)
    test(_TestSSLIsWriteableDuringHandshake)
    test(_TestStartTLSSendDuringUpgrade)
    test(_TestStartTLSIsWriteableDuringUpgrade)
    test(_TestStartTLSHandshakeFailure)
    test(_TestStartTLSAuthFailure)
    test(_TestSetTimerAfterTLSUpgrade)
    // POSIX only: these provoke write backpressure with a fixed payload, which
    // Windows loopback won't trigger (it buffers far beyond SO_SNDBUF/RCVBUF).
    // The drain and write-only re-arm logic they cover is platform-neutral.
    ifdef posix then test(_TestBackpressureDrain) end
    ifdef posix then test(_TestWriteOnlyEventReadRecovery) end
    ifdef posix then test(_TestSendPerTokenCompletion) end
    ifdef posix then test(_TestSendMidFlightDropBoundary) end
    ifdef posix then test(_TestSendSSLPerTokenCompletion) end
    ifdef posix then test(_TestSendSSLMidFlightDropBoundary) end
    ifdef posix then test(_TestSendGracefulCloseWithPending) end
    ifdef posix then test(_TestReadableEventWriteRecovery) end
