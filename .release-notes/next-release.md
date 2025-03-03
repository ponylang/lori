## Fix incorrect listen limit enforcement

The listen limit was being enforced incorrectly, causing the server to accept more connection concurrently than it should. This has been fixed.

## Fix possible memory leak

When hard closing a connection, we weren't clearing the list of pending data to send. By not doing that, if there was pending data to send, a lot of objects would be kept live and many things would not get garbage collected. This would result in "a memory leak".

It wasn't actually a leak. Everything in the Pony runtime was working as it should, we just were "doing a bad bad thing".

