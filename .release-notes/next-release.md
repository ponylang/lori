## Replace ponylang/ssl dependency with lori's own SSL types

SSL, DTLS, SSLContext, DTLSContext, X509, and the ALPN types are now part of the lori package. ponylang/ssl is no longer a dependency.

Drop any `use "ssl/net"` import. The types come through `use "lori"` and are not interchangeable with ponylang/ssl's ssl/net types.

Before:

```pony
use "lori"
use "ssl/net"

let ctx = SSLContext
```

After:

```pony
use "lori"

let ctx = SSLContext
```

