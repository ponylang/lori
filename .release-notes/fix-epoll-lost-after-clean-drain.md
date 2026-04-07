## Fix connection stall after large write with backpressure

A connection could stop processing incoming data after completing a large write that triggered backpressure. The connection would hang until either side closed it.
