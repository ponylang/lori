use "constrained_types"

primitive IdleTimeoutValidator is Validator[U64]
  """
  Validates that an idle timeout duration is greater than zero milliseconds.
  Used by `MakeIdleTimeout` to construct `IdleTimeout` values.
  """
  fun apply(value: U64): ValidationResult =>
    if value == 0 then
      recover val
        ValidationFailure(
          "idle timeout must be greater than zero")
      end
    else
      ValidationSuccess
    end

type IdleTimeout is Constrained[U64, IdleTimeoutValidator]
  """
  A validated idle timeout duration in milliseconds, guaranteed to be greater
  than zero. Construct with `MakeIdleTimeout(milliseconds)`, which returns
  `(IdleTimeout | ValidationFailure)`. Pass to `idle_timeout()` to set the
  timeout, or pass `None` to disable it.
  """

type MakeIdleTimeout is MakeConstrained[U64, IdleTimeoutValidator]
  """
  Factory for `IdleTimeout` values. Returns `(IdleTimeout | ValidationFailure)`.
  """
