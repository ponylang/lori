## Fix connection hang under sustained write backpressure

A connection could permanently stop making progress under sustained write backpressure while its peer was still sending — data stopped flowing in both directions and the connection never recovered on its own, staying wedged until it was closed. This affected echo, relay, and proxy-style connections that pause reading with `mute()` while a write is backed up, and was most likely to appear on multi-threaded runtimes. Such a connection now recovers and continues once the backpressure clears.
