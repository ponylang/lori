## Widen send() to accept multiple buffers via writev

`send()` now accepts `(ByteSeq | ByteSeqIter)`, allowing multiple buffers to be sent in a single writev syscall. This avoids both the per-buffer syscall overhead of calling `send()` multiple times and the cost of copying into a contiguous buffer.

```pony
// Single buffer — same as before
_tcp_connection.send("Hello, world!")

// Multiple buffers — one writev syscall
_tcp_connection.send(recover val [as ByteSeq: header; payload] end)
```

Internally, all writes now use writev, including single-buffer sends.

