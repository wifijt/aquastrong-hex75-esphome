#!/bin/bash
# Patches ESPHome's modbus component for noisy RS-485 buses (compressor VFD EMI)
# and stages it in YOUR repo, so the HA ESPHome dashboard can pull it via
# external_components (no shell access needed on the HA side).
#
# TWO PATCHES:
#   A) Response timeout becomes unconditional. Upstream refuses to time out
#      while a partial frame whose first byte matches the slave address is in
#      the buffer -- under noise this happens constantly, so the
#      "waiting for response" flag never clears and Tx is starved forever.
#   B) tx_blocked() drops the four noise-sensitive blocking conditions,
#      keeping only the two self-referential ones.
#   Patch A is required for Patch B to work: B keeps the "awaiting response"
#   check, which is only safe once A guarantees that flag actually clears.
#
# RUN ON YOUR LAPTOP from the root of your repo checkout, then commit + push.
# Re-run after upgrading ESPHome.
#
#   bash build-modbus-override.sh 2026.5.2

set -e
VERSION="${1:-2026.5.2}"

if [ ! -d .git ]; then
  echo "ERROR: run this from the root of your git repo checkout." >&2
  exit 1
fi

echo "Fetching modbus component from ESPHome $VERSION ..."
rm -rf .modbus_tmp components/modbus
mkdir -p components
git clone --depth 1 --branch "$VERSION" \
    https://github.com/esphome/esphome.git .modbus_tmp >/dev/null 2>&1
cp -r .modbus_tmp/esphome/components/modbus components/modbus
rm -rf .modbus_tmp

python3 - << 'PYEOF'
p = 'components/modbus/modbus.cpp'
src = open(p).read()

if 'LOCAL OVERRIDE' in src:
    raise SystemExit("Already patched - nothing to do.")

oldA = """  // If we're past the send_wait_time timeout and response buffer doesn't have the start of the expected response
  if (this->waiting_for_response_ != 0 &&
      millis() - this->last_send_ > this->last_send_tx_offset_ + this->send_wait_time_ &&
      (this->rx_buffer_.empty() || this->rx_buffer_[0] != this->waiting_for_response_)) {"""

newA = """  // LOCAL OVERRIDE (A): make the response timeout an unconditional timeout.
  // Upstream also required (rx_buffer_.empty() || rx_buffer_[0] != waiting_for_response_),
  // i.e. it refuses to give up while a partial frame whose first byte matches our
  // slave address sits in the buffer. Under RS-485 noise, corrupted fragments
  // frequently begin with the slave address, so waiting_for_response_ is never
  // cleared -- and tx_blocked() condition 3 then starves Tx indefinitely.
  // send_wait_time (250ms) is ~5x the longest legitimate reply on this bus
  // (21 registers = ~47 bytes = ~49ms at 9600 baud), so once it elapses,
  // giving up unconditionally is correct.
  if (this->waiting_for_response_ != 0 &&
      millis() - this->last_send_ > this->last_send_tx_offset_ + this->send_wait_time_) {"""

oldB = """  return this->available() || !this->rx_buffer_.empty() || (this->waiting_for_response_ != 0) ||
         (now - this->last_send_ < this->last_send_tx_offset_ + this->frame_delay_ms_ +
                                       (this->role == ModbusRole::CLIENT ? this->turnaround_delay_ms_ : 0)) ||
         (now - this->last_modbus_byte_ <
          this->frame_delay_ms_ + (this->role == ModbusRole::CLIENT ? this->turnaround_delay_ms_ : 0));"""

newB = """  // LOCAL OVERRIDE (B): drop the noise-sensitive blocking conditions 1, 2, 5, 6
  // (any Rx byte available / any byte in our Rx buffer / recent Rx byte /
  // turnaround delay). On a noisy single-slave RS-485 bus these are true
  // essentially always, starving Tx. Conditions 1 and 2 are NOT reachable
  // via the turnaround_time YAML option.
  // Kept: condition 3 (awaiting our own response - now bounded by the
  // unconditional timeout in Patch A) and condition 4 (our own frame tail).
  return (this->waiting_for_response_ != 0) ||
         (now - this->last_send_ < this->last_send_tx_offset_ + this->frame_delay_ms_);"""

for name, old in (("A", oldA), ("B", oldB)):
    if src.count(old) != 1:
        raise SystemExit(
            "ERROR: patch %s anchor not found/unique for ESPHome %s.\n"
            "The component source changed. Inspect manually - do not flash blind."
            % (name, "VERSION_PLACEHOLDER"))

src = src.replace(oldA, newA).replace(oldB, newB)
open(p, 'w').write(src)
print("Patched components/modbus/modbus.cpp (A: response timeout, B: tx gating)")
PYEOF

cat > components/README.md << 'MDEOF'
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
MDEOF

echo
echo "Done. Next:"
echo "  git add components/ build-modbus-override.sh"
echo "  git commit -m 'modbus override: unconditional response timeout + relaxed TX gating'"
echo "  git push origin main"
echo
echo "The ESPHome dashboard will pull the new version on next Install."
echo "(If it caches, bump the 'ref' or use a tag.)"
