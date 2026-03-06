primitive Success
  """A successful operation."""

primitive ReadBufferResizeBelowExpect
  """
  The requested read buffer size or minimum is smaller than the current
  expect value. The expect value sets a hard floor — the buffer must be
  able to hold at least that many bytes to satisfy the framing contract.
  """

primitive ReadBufferResizeBelowUsed
  """
  The requested read buffer size is smaller than the amount of unprocessed
  data currently in the buffer. Honoring the request would truncate data.
  """

type ReadBufferResizeResult is
  (Success | ReadBufferResizeBelowExpect | ReadBufferResizeBelowUsed)

primitive ExpectAboveBufferMinimum
  """
  The requested expect value exceeds the current read buffer minimum. Raise
  the buffer minimum first, then set expect.
  """

type ExpectResult is
  (Success | ExpectAboveBufferMinimum)
