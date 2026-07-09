## Fix mute() not stopping data delivery on SSL connections

Calling `mute()` from `_on_received` stops a plaintext connection delivering data right there. An SSL connection kept going: every remaining decrypted message from the same read arrived anyway. An application that mutes because it can't keep up got handed more data regardless.

`mute()` now stops delivery on an SSL connection as soon as the application calls it. Messages already decrypted but not yet delivered are held, not dropped, and `unmute()` delivers them before anything read off the socket afterward. Closing a muted connection still drops them, as it always has for a muted plaintext connection.
