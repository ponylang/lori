primitive BitSet
  fun set(bits: U32, position: U32): U32 =>
    bits or (1 << position)

  fun unset(bits: U32, position: U32): U32 =>
    bits and not (1 << position)

  fun is_set(bits: U32, position: U32): Bool =>
    ((bits >> position) and 1) != 0
