# Stress Tests

Tests designed to run for an extended period of time that should stress some aspect of Lori.

- **tcp-swarm** -- Heavy TCP connection churn with a content oracle. Exercises the
  full TCP connection lifecycle (connect, send, echo-verify, close) with swarm
  draws across write shapes, payload sizes, and read-loop tuning.

- **udp-flood** -- Sustained UDP datagram volume with a content oracle. Multiple
  clients flood datagrams through a single echo server, exercising the persistent
  edge-triggered readiness event path under load. Written to verify that each
  platform's ASIO backend (ProcessSocketNotifications on Windows, epoll on Linux,
  kqueue on macOS) delivers UDP events correctly under stress.
