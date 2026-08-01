## Fix a file descriptor being closed twice on macOS

On macOS, a client connection to a host that resolves to more than one address — `localhost` is one — could close one of its own file descriptors twice while cleaning up the connection attempts it did not use. The operating system can hand that descriptor number to something else in your program in between, and the second close then lands on whatever got it: an unrelated connection or file closes, and nothing reports why.

The same cleanup also miscounted how many connection attempts were still outstanding. That could abandon an attempt that was still running and report the connection as failed, hand `_on_connecting` a count of 4294967295, or leave a connection that was asked to close gracefully never sending its FIN and never finishing.

Linux and Windows were not affected. macOS can deliver two readiness notifications for a single connection attempt where they deliver one, and the second one was being treated as a second attempt.
