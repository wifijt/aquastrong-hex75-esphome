#!/bin/bash
# Builds a patched copy of ESPHome's modbus component into YOUR repo, so the
# HA ESPHome dashboard can pull it via external_components (no shell needed
# on the HA side).
#
# RUN THIS ON YOUR LAPTOP, from the root of your aquastrong-hex75-esphome
# checkout. Then commit + push. Re-run after upgrading ESPHome.
#
#   ./build-modbus-override.sh 2026.5.2

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

old = """  return this->available() || !this->rx_buffer_.empty() || (this->waiting_for_response_ != 0) ||
         (now - this->last_send_ < this->last_send_tx_offset_ + this->frame_delay_ms_ +
                                       (this->role == ModbusRole::CLIENT ? this->turnaround_delay_ms_ : 0)) ||
         (now - this->last_modbus_byte_ <
          this->frame_delay_ms_ + (this->role == ModbusRole::CLIENT ? this->turnaround_delay_ms_ : 0));"""

new = """  // LOCAL OVERRIDE - reverted toward pre-2026.3.0 "talk over noise" behavior.
  // Dropped conditions 1, 2, 5, 6 (any Rx byte present / recent Rx byte /
  // turnaround delay). On a single-slave RS-485 bus with compressor VFD noise
  // these keep the Rx buffer permanently non-empty and starve Tx indefinitely,
  // making it impossible to deliver a power-off command while the compressor
  // is running. Conditions 1 and 2 are NOT tunable via turnaround_time.
  // Kept conditions 3 and 4: both are self-referential (our own pending
  // response, our own frame tail) and never noise-dependent.
  return (this->waiting_for_response_ != 0) ||
         (now - this->last_send_ < this->last_send_tx_offset_ + this->frame_delay_ms_);"""

if 'LOCAL OVERRIDE' in src:
    print("Already patched.")
elif src.count(old) == 1:
    open(p, 'w').write(src.replace(old, new))
    print("Patched components/modbus/modbus.cpp")
else:
    raise SystemExit("ERROR: tx_blocked() differs from expected for ESPHome "
                     + "$VERSION" + " - inspect and patch manually. Do not flash blind.")
PYEOF

cat > components/README.md << 'MDEOF'
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
MDEOF

echo
echo "Done. Next:"
echo "  git add components/ build-modbus-override.sh"
echo "  git commit -m 'Add patched modbus component (pre-2026.3 TX behavior)'"
echo "  git push origin main"
echo
echo "Then in the ESPHome dashboard YAML, add:"
echo
echo "external_components:"
echo "  - source:"
echo "      type: git"
echo "      url: https://github.com/wifijt/aquastrong-hex75-esphome"
echo "      ref: main"
echo "    components: [modbus]"
