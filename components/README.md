# Patched `modbus` component

A copy of ESPHome's `modbus` component with two changes for electrically
noisy RS-485 buses (compressor VFD EMI). Both are in `modbus.cpp`, marked
`LOCAL OVERRIDE`.

## Patch A — unconditional response timeout (`loop()`)

Upstream clears the "waiting for response" flag only when the send timeout
has elapsed **and** the Rx buffer is empty or doesn't start with the slave
address. Under noise, corrupted fragments frequently begin with the slave
address byte, so the flag is never cleared. Since an outstanding response
also blocks transmission, this starves Tx indefinitely — observed as
20+ seconds of "...ms after last send" with zero
"Stop waiting for response" log lines.

`send_wait_time` (250ms) is roughly 5x the longest legitimate reply on this
bus, so once it elapses, giving up unconditionally is correct.

## Patch B — `tx_blocked()`

ESPHome 2026.3.0 changed transmit arbitration to refuse transmission while
any byte is in the Rx buffer, or within `frame_delay + turnaround_time` of
the last received byte. The first two conditions are **not** configurable
via `turnaround_time`, so YAML tuning alone cannot fix severe cases.

This copy drops the four noise-sensitive conditions and keeps the two
self-referential ones (awaiting our own response — bounded by Patch A;
and our own frame tail). Corrupted frames are still caught by CRC and
handled by the normal retry path.

## Maintenance

Regenerate with `build-modbus-override.sh <esphome-version>` after
upgrading ESPHome — this copy is pinned to the version it was built from.
The script refuses to patch if upstream source has changed.
