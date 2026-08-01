primitive _FETrace
  """
  Temporary diagnostic. Not for merge.
  """
  fun dispatch(state: _ConnectionState box,
    event: AsioEventID,
    flags: U32,
    inflight: U32)
  =>
    @fprintf(
      @pony_os_stderr(),
      "LORI ev=%p fd=%s flags=%s disposed=%s state=%s inflight=%s\n".cstring(),
      event,
      PonyAsio.event_fd(event).string().cstring(),
      flags.string().cstring(),
      PonyAsio.get_disposable(event).string().cstring(),
      name(state).cstring(),
      inflight.string().cstring())

  fun started(count: U32) =>
    @fprintf(
      @pony_os_stderr(),
      "LORI connect started attempts=%s\n".cstring(),
      count.string().cstring())

  fun name(state: _ConnectionState box): String =>
    match state
    | let _: _ConnectionNone box => "ConnectionNone"
    | let _: _ClientConnecting box => "ClientConnecting"
    | let _: _Open box => "Open"
    | let _: _Closing box => "Closing"
    | let _: _UnconnectedClosing box => "UnconnectedClosing"
    | let _: _Closed box => "Closed"
    | let _: _SSLHandshaking box => "SSLHandshaking"
    | let _: _TLSUpgrading box => "TLSUpgrading"
    else
      "unknown"
    end
