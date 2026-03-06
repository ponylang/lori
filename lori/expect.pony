use "constrained_types"

primitive ExpectValidator is Validator[USize]
  """
  Validates that an expect value is at least 1.

  An expect of 0 is meaningless — use `None` to indicate "deliver all available
  data." Used by `MakeExpect` to construct `Expect` values.
  """
  fun apply(value: USize): ValidationResult =>
    if value == 0 then
      recover val
        ValidationFailure("expect must be greater than zero")
      end
    else
      ValidationSuccess
    end

type Expect is Constrained[USize, ExpectValidator]
  """
  A validated expect value in bytes. The value must be at least 1.

  Construct with `MakeExpect(bytes)`, which returns
  `(Expect | ValidationFailure)`. Pass to `TCPConnection.expect()`.
  Use `None` instead of `Expect` to indicate "deliver all available data."
  """

type MakeExpect is MakeConstrained[USize, ExpectValidator]
  """
  Factory for `Expect` values. Returns `(Expect | ValidationFailure)`.
  """
