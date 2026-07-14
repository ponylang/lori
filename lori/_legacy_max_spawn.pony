use "constrained_types"

primitive _LegacyMaxSpawn
  fun apply(limit: USize): (MaxSpawn | None) =>
    """
    Convert a raw `USize` connection limit (the stdlib API, 0 = unlimited) into
    lori's `(MaxSpawn | None)`. 0 maps to `None` (no limit). lori's `MaxSpawn`
    is a `U32`, so a limit above `U32.max_value()` is clamped to it rather than
    silently truncated.
    """
    if limit == 0 then
      None
    else
      let clamped = limit.min(U32.max_value().usize()).u32()
      match \exhaustive\ MakeMaxSpawn(clamped)
      | let m: MaxSpawn => m
      | let _: ValidationFailure => None
      end
    end
