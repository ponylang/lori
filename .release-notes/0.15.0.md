## Require ponyc 0.64.0 or later

lori now requires ponyc 0.64.0 or later. The previous minimum was 0.63.1.

This is driven by changes in ponyc 0.64.0 to FFI declaration syntax and the runtime socket API that lori depends on. Older ponyc versions will fail to compile lori.

