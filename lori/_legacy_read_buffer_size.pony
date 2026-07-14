use "constrained_types"

primitive _LegacyReadBufferSize
  fun apply(size: USize): ReadBufferSize =>
    """
    Convert a raw `USize` (the stdlib API's read buffer size) into lori's
    constrained `ReadBufferSize`. A value lori rejects (0) falls back to the
    default, since an actor constructor cannot fail.
    """
    match \exhaustive\ MakeReadBufferSize(size)
    | let r: ReadBufferSize => r
    | let _: ValidationFailure => DefaultReadBufferSize()
    end
