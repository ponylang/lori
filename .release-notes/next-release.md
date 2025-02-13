## Fix a Server Shutdown Race Condition

There was a race condition in the server shutdown logic that could cause a `TCPServerActor` to treat a socket as closed before all data was read from it. The end result would be the early termination of a new connection that shared the file descriptor with the previous connection. For most user applications, this would be seen as the server having a hung connection.

## Fix a "Data Never Seen on Server Start" Race Condition

There was a race condition when starting a `TCPServerActor` that could result in a hang. Sometimes, all data for the server would arrive before the server had set up its file descriptor with the ASIO system. If no other data was sent by the client, then the server would never read the data and everyone would hang waiting on someone to do something.
