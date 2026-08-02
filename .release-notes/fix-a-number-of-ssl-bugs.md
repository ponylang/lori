## Fix a number of SSL bugs

Fixed multiple bugs affecting SSL support, including handshake failures being reported as authentication failures, data being silently dropped on large writes and when encryption fails, and connections being closed by unrelated SSL failures elsewhere.
