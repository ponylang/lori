primitive BitSet
  fun set(bits: U32, position: U32): U32 =>
    bits xor ((-1 xor bits) and (1 << position))

  fun unset(bits: U32, position: U32): U32 =>
    bits xor ((-0 xor bits) and (1 << position))

  fun is_set(bits: U32, position: U32): Bool =>
    ((bits >> position) and 1) != 0
