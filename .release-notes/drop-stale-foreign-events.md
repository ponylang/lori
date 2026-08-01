## Fix a file descriptor being closed twice on macOS

On macOS, setting up a client connection could close one of its own file descriptors twice. The operating system can hand that descriptor number to something else in your program in between, and the second close then lands on whatever got it: an unrelated connection or file closes, and nothing reports why. A connection to a host that resolves to more than one address is the likeliest way to hit it — `localhost` is one — but a single-address connection that fails hits it too.

The same cleanup also miscounted how many connection attempts were still outstanding. That could abandon an attempt that was still running and report the connection as failed, tell `_on_connecting` that fewer attempts were in progress than really were, or leave a connection that was asked to close gracefully never sending its FIN and never finishing.

Linux and Windows were not affected. macOS can deliver two readiness notifications for a single connection attempt where they deliver one, and the second was being treated as a second attempt.
