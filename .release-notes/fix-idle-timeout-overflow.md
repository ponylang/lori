## Fix wraparound error going from milli to nano in IdleTimeout

`IdleTimeout` now enforces a maximum value of 18,446,744,073,709 milliseconds (~213,503 days). Previously, very large millisecond values would silently overflow when converted to nanoseconds internally, resulting in an incorrect (much shorter) timeout. Values above the maximum are now rejected during construction with a `ValidationFailure`.
