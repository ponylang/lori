## Widen send() to accept multiple buffers via writev

`send()` now accepts `(ByteSeq | ByteSeqIter)`, allowing multiple buffers to be sent in a single writev syscall. This avoids both the per-buffer syscall overhead of calling `send()` multiple times and the cost of copying into a contiguous buffer.

```pony
// Single buffer — same as before
_tcp_connection.send("Hello, world!")

// Multiple buffers — one writev syscall
_tcp_connection.send(recover val [as ByteSeq: header; payload] end)
```

Internally, all writes now use writev, including single-buffer sends.

## Fix FFI declarations for exit() and pony_os_stderr()

The FFI declarations for `exit()` and `pony_os_stderr()` used incorrect types (`U8` instead of `I32` for the exit status, `Pointer[U8]` instead of `Pointer[None]` for the `FILE*` stream pointer). This caused compilation failures when lori was used alongside other packages that declare the same FFI functions with the correct C types.

