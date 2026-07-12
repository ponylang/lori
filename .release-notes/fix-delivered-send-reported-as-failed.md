## Fix a delivered send being reported as failed on a hard close

`_on_send_failed` says a send never left. On a hard close it could arrive for a send whose bytes had already been handed to the OS.

An application that hard closes from `_on_throttled` fails every send still queued, and one of those could be a send the write flush had just finished. So the split between `_on_sent` and `_on_send_failed` — which is there to tell you how far your data actually got — could report a delivered send as never sent, and an application acting on it would resend bytes the peer may already have had.

Completed sends are now reported before `_on_throttled` runs, so the split means what it says.
