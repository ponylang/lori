## Add NetAddress, DNS, and DNSAuth

`NetAddress`, `DNS`, and `DNSAuth` are now part of lori.

`DNS` provides synchronous name resolution via `getaddrinfo`, broadcast address lookup, and IP literal detection (`is_ip4`/`is_ip6`). `DNSAuth` is created from `AmbientAuth` or `NetAuth`.

## Drop use net = "net" in favor of lori's own NetAddress and DNS

Code that imported stdlib's `net` package for `NetAddress` should drop the `use net = "net"` import and use the unqualified names. Code that uses both `use "lori"` and `use "net"` will get ambiguous `NetAddress`, `DNS`, and `DNSAuth` types.

Before:

```pony
use "lori"
use net = "net"

fun ref local_address(): net.NetAddress =>
  // ...
```

After:

```pony
use "lori"

fun ref local_address(): NetAddress =>
  // ...
```
