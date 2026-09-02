# UDP flood stress engine

A count-driven UDP workload for stressing lori's UDP stack. A fixed number of
clients send stamped datagrams to a server through a single echo socket; the
server echoes each datagram back to its sender, and the client verifies the
echo byte-for-byte against a per-client keystream.

This stress test was written to empirically verify that the ASIO backend
delivers persistent edge-triggered notifications correctly for UDP sockets
under sustained load.

## How it stresses lori

No connection lifecycle: UDP sockets bind, send, receive, and close. The point
is to exercise the readiness event delivery path under sustained datagram
volume, verifying that the ASIO backend correctly delivers persistent
edge-triggered notifications for UDP sockets across many read-loop re-entries.
Each flag is tied to a distinct code path in `udp_socket.pony`:

- `--datagrams` / `--payload-size` -- volume and per-datagram size.
- `--batch-size` -- how many datagrams a client sends before waiting for echoes.
  With batch 1 the client waits for each echo before sending the next (one
  event delivery per round-trip). Larger batches burst datagrams and exercise
  the read loop's datagram-count and byte budgets.
- `--clients` -- concurrent client sockets sending to the same server.
- `--read-buffer-size` -- the per-socket read buffer, which sets the byte
  budget in `_pending_reads`.
- `--max-datagrams-per-turn` -- the per-turn datagram ceiling in
  `_pending_reads`. Small values exercise the `_read_again` yield path.

## Oracles

- **Echo integrity** -- each client sends a per-client pseudo-random byte
  stream (the byte at position `p` is the low 8 bits of a splitmix64 hash of
  the client id and `p`) and verifies every echoed byte against it.
  Position-based: the Nth echo must match the Nth datagram sent (UDP preserves
  order on loopback).
- **Conservation** -- every client must send and verify all its datagrams; the
  `RESULT` line reports the tally.
- **Crash / assert** -- debug build, asserts on.

On success (every client verified) the engine prints `RESULT ...` then `PASS`
and returns. Anything short of full verification prints `FAIL` and exits
non-zero.

## Building and running

The engine is built by the project Makefile, which discovers this directory
automatically:

```bash
make stress-tests config=debug ssl=3.0.x     # -> build/debug/udp-flood
```

Run the engine directly for a single workload:

```bash
build/debug/udp-flood --datagrams 1000 --clients 8 --payload-size 256 \
  --batch-size 10
```

Every flag is checked against a schema and its valid range. `--help` lists them.

## Running the swarm

The orchestrator draws one workload per seed and runs the prebuilt engine once
per seed. It does not compile; point `--binary` at the engine you built above.

```bash
python3 stress-tests/udp-flood/orchestrate_udp.py \
  --binary build/debug/udp-flood --count 50 --out ~/tmp/udp-flood-out
```

The draw is stable per seed. Selectors:

- `--count N` / `--start S` -- run N seeds from S.
- `--seeds A,B,C` -- run specific seeds.
- `--replay N` -- reproduce seed N's workload.
- `--budget-seconds N` -- run seeds from `--start` until N seconds pass.
- `--lldb <path>` -- run each seed under lldb so a crash leaves a backtrace.

A run is a failure only if it crashes, mismatches, or hangs. A failure writes
`bundle-<seed>.json` to `--out`. A healthy run is never failed for running long:
one still making progress at the `--timeout-seconds` backstop is reported
`incomplete`, not failed.

`orchestrate_udp_test.py` covers the pure pieces: `python3 orchestrate_udp_test.py`.
