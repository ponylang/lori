## Rename expect() to buffer_until() with clearer type names

The `expect()` method on `TCPConnection` has been renamed to `buffer_until()` to better convey its semantics: "buffer data until you have this many bytes, then deliver." The `None` sentinel that meant "deliver all available data" is replaced by an explicit `Streaming` primitive.

Before:

```pony
match MakeExpect(4)
| let e: Expect => _tcp_connection.expect(e)
end

// streaming mode
_tcp_connection.expect(None)
```

After:

```pony
match MakeBufferSize(4)
| let e: BufferSize => _tcp_connection.buffer_until(e)
end

// streaming mode
_tcp_connection.buffer_until(Streaming)
```

Full rename mapping:

| Old | New |
|-----|-----|
| `expect(qty)` | `buffer_until(qty)` |
| `Expect` | `BufferSize` |
| `MakeExpect` | `MakeBufferSize` |
| `None` (in expect context) | `Streaming` |
| `ExpectSet` | `BufferUntilSet` |
| `ExpectAboveBufferMinimum` | `BufferSizeAboveMinimum` |
| `ExpectResult` | `BufferUntilResult` |
| `ReadBufferResizeBelowExpect` | `ReadBufferResizeBelowBufferSize` |
