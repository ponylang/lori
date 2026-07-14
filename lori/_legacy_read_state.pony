class _LegacyReadState
  """
  Per-connection read-yield bookkeeping for a Legacy connection: the receive
  count reported to the notifier as `times`, and the bytes delivered since the
  last yield. The client and accepted-connection actors each own one and share
  the yield policy through `_LegacyConnection._deliver_received`.
  """
  var count: USize = 0
  var bytes: USize = 0
  let yield_after: USize

  new create(yield_after': USize) =>
    yield_after = yield_after'
