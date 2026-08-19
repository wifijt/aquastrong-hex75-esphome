# Patched `modbus` component

A copy of ESPHome's `modbus` component with one change to `tx_blocked()`.

ESPHome 2026.3.0 changed Modbus transmit arbitration to refuse transmission
while **any** byte is present in the Rx buffer, or within
`frame_delay + turnaround_time` of the last received byte. On an
electrically noisy RS-485 bus (compressor VFD EMI), the Rx buffer is
effectively never empty, so the ESP can be starved of transmit
opportunities indefinitely — including for power-off commands.

The first two blocking conditions are **not** configurable via
`turnaround_time`, so YAML tuning alone cannot resolve severe cases.

This copy drops the four noise-sensitive blocking conditions and keeps the
two self-referential ones (awaiting our own response; our own frame tail),
approximating pre-2026.3.0 behavior. Corrupted frames are still caught by
CRC and handled by the normal retry path.

Regenerate with `build-modbus-override.sh <esphome-version>` after
upgrading ESPHome — this copy is pinned to the version it was built from.
