## Make `TCPListenerActor.on_closed` private

This method is not intended to be called by users of the library, so it should be made private.

Any listener's that you've implemented that implemented `on_closed` need to be updated to override `_on_closed` instead. Failing to do so will result in programs that hang.
