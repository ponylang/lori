## Fix FFI declarations for exit() and pony_os_stderr()

The FFI declarations for `exit()` and `pony_os_stderr()` used incorrect types (`U8` instead of `I32` for the exit status, `Pointer[U8]` instead of `Pointer[None]` for the `FILE*` stream pointer). This caused compilation failures when lori was used alongside other packages that declare the same FFI functions with the correct C types.

