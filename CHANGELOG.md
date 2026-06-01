# Changelog

## v1.1.0 — Register map expansion and flow status clarification

### New findings

**Water flow boolean (reg 98) confirmed:**
- Register 98 = dedicated water flow boolean: **1 = flow present, 0 = no flow**
- Confirmed by three deliberate flow-off tests with before/after diffs
- Cleaner and more direct than deriving flow state from reg 29
- Exposed as `Pool Heater Water Flow` binary sensor (device_class: running)

**Protection status block (regs 96-99):**
- Registers 96, 97, 98, 99 form a protection status block
- Pattern: **1 = OK, 0 = fault/protection active**
- Reg 98 = E03 water flow confirmed; regs 96, 97, 99 = TBD (candidates: high pressure, low pressure, phase)

**Reg 29 reframed — flow sensor state, not fault code:**
- 255 = flow switch closed (water flowing) — normal
- 511 = flow switch open (no water) — normal when unit off, E03 only when unit is ON
- The display and Tuya apply context: 511 is only surfaced as E03 when unit is powered on
- `Fault Active` binary sensor updated to exclude 511 when unit is off

**New `Pool Heater Fault` text sensor:**
- Shows: `Off` / `OK` / `E03 Water Flow` / `Fault 0xXXXX (NNN)` for unknown values
- Unknown faults log both hex and decimal for identification

**Running state map expanded:**
- 0x1C (28) = post-shutdown equalization (EEV equalizing, fan clearing heat)
- 0x1D (29) = protection mode, startup dwell, or running low-mid load (not reliable alone)
- 0x1E (30) = ramping up (compressor spinning up)
- Previously known: 0x20=idle, 0x21=running heat, 0x22=transitional, 0x23=cool

**Reg 68 = AC input voltage (confirmed hypothesis):**
- Stable ~239-244V under all load conditions
- Drops ~3V when compressor stops (line voltage rises as current draw falls)
- Consistent with residential 240V supply measurement

**Reg 69 = compressor load metric:**
- Scales ~1.5-1.7× compressor frequency across all observed operating points
- Likely input current in 0.1A units (e.g. 120 = 12.0A at 70Hz)

**Historical session log ranges documented (376-557):**
- Registers 376-448: session log — ascending water temp sequence, sensor snapshot, compressor ramp-down. Updates at end of run cycle only, not real-time
- Registers 449-557: efficiency/COP metrics per historical session + frequency mirrors (553-556 = fan Hz, 557 = compressor Hz)
- Neither range changes during fault events — confirmed not fault registers

**Structured data block (2048-2063):**
- Possible firmware version/timestamp; reg 2060 mirrors upper setpoint bound
- Does not change during fault events

**Confirmed empty ranges:**
- Registers 100-164: all zero on this firmware
- Registers 256-264, 266-269, 281-283, 295: all zero
- Registers 404-405, 411-416, 419-424: all zero

### YAML changes

- Duplicate sensor block (regs 100-149) removed
- `force_new_range: true` added to Running State (785) and Diag Reg 2056 to fix duplicate Modbus command warnings
- `Pool Heater Water Flow Fault` binary sensor replaced with `Pool Heater Water Flow` (device_class: running, sourced from reg 98)
- `Pool Heater Fault Active` updated to exclude 511 when unit is off
- `Pool Heater Fault` text sensor added (human-readable fault decoding)
- `Pool Heater Water Flow Sensor` (reg 98 raw value) added
- All confirmed-zero diagnostic registers removed from YAML
- New diagnostic registers added: 96-99, 265, 270-280, 284-303, 376-448, 449-557, 2048-2063
- Version bumped to 1.0.0 in ESPHome project metadata

### Known issues

- Regs 96, 97, 99 protection bits unconfirmed — need other fault conditions to trigger (E05, E06, phase)
- Reg 83 purpose unknown — always 1 when powered
- Only E03 fault value confirmed in reg 29; other E-codes need natural fault events
- Defrost mode still unidentified
- Energy Total counter occasionally shows brief decreases during fault events

---

## v1.0.0 — Initial public release

First public release of the integration.

### Features

- Full Modbus RTU read/write integration with the CHICO SMBPRO53 controller
- All sensors mapped and validated against OEM display ground truth:
  - Ambient, Coiler, Incoiler, Suction, Discharge temperatures
  - Inlet/Outlet water temperatures with verified delta T
  - Compressor and fan frequencies, EEV opening
  - Energy total (kWh)
  - Active heating indicator
  - Fault code with water flow protection bit decoded
- Full control set:
  - Power on/off
  - Mode selection (Cool/Heat/Auto)
  - Energy mode (Standard/Boost/Eco)
  - Setpoints for all three modes
- Write confirmation with retry and error surfacing
- Idle state sync (HA always reflects controller state)
- Web server diagnostic view at `http://pool-heatpump.local/`
- Documented protocol for community use

### Known issues

- Several registers' purposes still unknown (68, 69, 71, 83)
- Only one fault bit (water flow protection, 0x100) is decoded
- Defrost mode is not yet detectable — the Tuya app shows a "Defrosting" status but the underlying register hasn't been identified
- The "Energy Total" counter occasionally shows brief decreases during fault events
