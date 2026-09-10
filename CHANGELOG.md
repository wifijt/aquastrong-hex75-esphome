# Changelog

## v1.3.0 — Register decode corrections

Three registers were carrying wrong labels. All corrections below were
established by regression against an external power meter on the heat pump
feed and against whole-pool energy balance, over two full run cycles
(1499 sampled points), then reproduced on a third.

### Corrected registers

| Reg | Was | Is | Evidence |
|---|---|---|---|
| 72 | `Energy Total` (kWh, ×0.01) | **DC bus voltage** (V) | Idle 336 = √2 × 237Vac; running 377–380 regulated; precharge dip to 327 on start; back to 336 within 5s of stop. Never accumulates. |
| 69 | `Compressor Load` (raw) | **AC input current** (×0.1 A) | `VA = 0.09501 × (reg69 × reg68)`, r²=0.9702 — beats the pure-power fit, the signature of a current. |
| 71 | `Refrigerant Metric` (raw) | **Condensing temp** (°F) | Idle equalises between water and ambient; running mean 101; collapses 104→78 within 2 min of shutdown. |

**If you were feeding reg 72 into the HA energy dashboard, remove it.** It
was never energy — the values are bus volts, and they do not accumulate.

### Corrected labels (no functional change)

- Regs 272 / 274 / 275 were labelled `Runtime Counter` / `Pressure A` /
  `Pressure B`. All three are **static constants** (998 / 86 / 90),
  unchanged across 5 days of logging including a full 8.5h run. Renamed to
  `Static Reg N` and marked diagnostic. Still polled once a minute in case
  they move during an E05/E06 pressure fault.
- Reg 70 keeps the name `Active Heating` — the boolean derivative is
  correct — but the scalar is explicitly **not decoded**. It is not a power
  proxy (r²=0.59 against measured input power). Do not scale it.
- `docs/PROTOCOL.md` claimed reg 68 was post-PFC and rose under load. It
  does not: idle mean 236.9V, running mean 237.3V. It is plain RMS line
  voltage. The PFC bus is reg 72.

### New

- **Input Apparent Power** (VA), derived as reg 68 × reg 69. Exact by
  definition; matched the reference meter at r²=0.9702.
- **Evaporator Superheat** (°F) = suction − coiler. Measured 2–3 °F and
  rock steady across every run logged; a sustained drift means charge or
  expansion valve.
- **Discharge Superheat** (°F) = discharge − condensing. Observed 85→68 °F
  on one run, 62→56 °F on another. A rising trend at matched conditions is
  the classic undercharge signature.
- **Condenser Approach** (°F) = condensing − outlet water. Observed 13–18 °F
  on one run and 24–25 °F on another at identical compressor speed and
  input power. Probably explained by the higher ambient raising capacity —
  but if it climbs at matched conditions it means fouling or reduced flow,
  and the reg 71 decode needs revisiting.
- **Defrosting** (binary). This controller has no known defrost register and
  does not need one: defrost stops the outdoor fan while the compressor
  keeps running, and in every run logged the fan has never been at zero
  while the compressor turns. Heat mode only, 30s debounce both ways.
- **Protection Status** (text). Names whichever of regs 96/97/98/99 is low.
  96/97/99 have read 1 continuously for the life of this integration, so
  this is the mechanism by which we will finally learn what they mean.

All of the above are derived from registers already polled — no additional
Modbus frames.

### Register survey results (docs only)

Ranges 0-59 and 786-800 — never previously read — were swept across a
commanded shutdown and restart. This decoded the inverter control chain:

- **reg 39** = compressor demand frequency (the control law's output)
- **reg 40** = ramp-limited setpoint, rate-limited to **5 Hz per 5 s on
  deceleration**; steps directly to demand on acceleration
- **reg 64** (already known) = measured actual, chasing reg 40
- **regs 0, 1, 25, 26** = command bitfields. Every bit *leads* the physical
  event: the fan command bit sets 5.2s before the fan spins, the compressor
  bit 0.3s before the compressor turns.
- **regs 33, 34** = unpopulated sensor inputs, reading -1 as S_WORD
- **regs 30, 36, 786** = static constants

Regs 0 and 1 are single bits in otherwise-empty 16-bit words at the bottom of
the address space — the shape of a fault bitmap, and the most promising place
yet found for the undecoded E-codes and the defrost flag. Bit 12 of reg 0 and
bit 5 of reg 1 mean "run demand"; the other 30 bits are unmapped because this
unit has not faulted.

Also corrects the 785 state map: value 35 was listed as "cool mode related".
It is the heat-mode startup dwell, observed throughout a restart delay.

None of this changes the shipped config — see `tools/register-survey.yaml` to
reproduce it.

### Home Assistant metadata

Every sensor now declares `device_class` / `state_class` / `accuracy_decimals`
where applicable (15 / 17 / 16 respectively). Previously none did, which
meant **no long-term statistics for any sensor** — no history graphs beyond
the recorder window, no unit conversion, no energy dashboard eligibility.
Protection bits, running state and the static registers are now
`entity_category: diagnostic`.

### Fixed

- The restart button was named `"${friendly_name} Restart"` with no
  `substitutions:` block, so the literal `${friendly_name}` reached Home
  Assistant. Now `"Restart"`, which ESPHome prefixes automatically.

### Upgrading

Renaming a sensor changes its entity ID and orphans the old entity. Affected:
`energy_total`, `compressor_load`, `refrigerant_metric`, `runtime_counter`,
`pressure_a`, `pressure_b`, and the restart button. Update any dashboard
cards, automations or templates that reference them before flashing.

## v1.2.0 — Bus resilience under EMI / ESPHome 2026.3.0+ compatibility

### Critical fix: TX starvation on ESPHome 2026.3.0+

**If you upgraded ESPHome past 2026.3.0 and the device stops responding to
commands while the compressor runs, this release is the fix.**

ESPHome 2026.3.0 rewrote the `modbus` component's transmit arbitration.
The old component transmitted unconditionally; the new one refuses to
transmit until the line has been idle for `frame_delay + turnaround_time`
after **any** received byte. With the default `turnaround_time: 100ms`,
noise arriving at just ~10 bytes/second blocks transmission permanently.
Compressor VFD noise exceeds this easily — the result is an ESP that can
read nothing and, worse, cannot deliver a power-off command while the
compressor is generating the very noise that blocks it.

Fix: `turnaround_time: 5ms` on the `modbus:` component. This shrinks the
post-receive blackout to ~9ms, restoring most of the pre-2026.3
talk-over-noise tolerance. `command_throttle` already paces the
single-slave bus, so nothing of value is lost.

### Bus-failure resilience (defense in depth)

- `offline_skip_updates: 10` — when a command exhausts retries, all read
  polling is suppressed for 10 cycles, draining the queue so pending
  writes get a clear path
- Pending writes are now **held during outages** (the 10s rejection error
  only fires while the bus is online) and **resent automatically the
  moment the bus recovers** (`on_online` hook)
- Confirmation watchdog moved to a 5s timer so write retry/error
  reporting works even when no reads succeed
- Confirmation semantics hardened: a write is only confirmed when a
  control-block read occurred **after** the write request
  (`last_ctrl_read_ts >= pending_ts`), eliminating false self-confirmation
  against the optimistic cache
- Control entities are never published from boot-default cache values
- Watchdog: automatic reboot only after 5 continuous minutes offline

### Register map / performance

- **Frame consolidation:** padded gaps in the 64-84 and 768-779 blocks so
  each reads as a single Modbus frame. 5 frames per cycle vs ~10 before —
  frame count (throttle slots) dominates bus time, not data bytes
- New sensors: AC Voltage (reg 68), Compressor Load (reg 69), Refrigerant
  Metric (reg 71), Protection Bits 96/97/99 (fault hunters: 1=OK, 0=fault)
- New slow diagnostics (60s): Runtime Counter (reg 272), Pressure A/B
  (regs 274/275 — refrigerant pressure candidates for future E05/E06
  fault identification)
- Update interval 2s → 5s
- Note: reg 68 reads ~238V idle / ~243V running — measured post-PFC
  stage, not raw line voltage (rises when PFC boost is active)

### Housekeeping

- All commented-out diagnostic scan blocks removed (2,487 → ~1,100 lines);
  full scan blocks remain in git history for future decode sessions


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
