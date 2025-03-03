## Don't accept new connection after closing listener

Listeners had the possibility of accepting new connections that were already queued prior to closing the listener. This has been fixed and listeners will no longer accept new connections after closing.

The previous logic was fine except in the case of connection in the listen queue prior to closing.

