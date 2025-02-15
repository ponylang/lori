## Add callback for when a server is starting up

We've added a callback for when a server is starting up. This callback is called after the server has accepted a connection and before the server starts processing the request. This allows you to any protocol specific setup before the server starts processing the request. For example, this would be where an SSL handshake would be done.
