## Fix a hang when closing a connection while handling received data

Closing a connection from inside `_on_received` — for example, closing once you've read a full message — could leave the connection attempting one more read on the socket it had just closed. Under connection churn (many connections opening and closing), that stray read could block one of the runtime's scheduler threads and keep the program from exiting.

Closing a connection while handling received data no longer triggers this hang.
