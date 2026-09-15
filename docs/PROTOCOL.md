# Modbus Protocol Reference

This is the reverse-engineered Modbus RTU protocol for the CHICO SMBPRO53 V1.44 controller (PCB marked **`R-SY013-BP`**) as found in the Aquastrong HEX 75. It's likely substantially the same across the OEM family (Fairland, IPS, Poolsystems, Aquark) but exact compatibility is unconfirmed.

If your controller PCB is marked `R-SY013-BP`, this protocol map should apply directly. Similar boards from the same OEM may use the same protocol with minor variations.

## Temperature units

**This integration was developed on a unit configured to report in °F.** All setpoint registers and temperature sensors return values in °F natively — no conversion is applied in the ESPHome config.

If your unit is configured for °C, it presumably reports all temperature registers in °C instead. In that case:
- Update `unit_of_measurement: "°F"` to `unit_of_measurement: "°C"` on all temperature sensors in the YAML
- Update the setpoint ranges in the `number:` entities accordingly (47-83°F → ~8-28°C for Cool, etc.)

The °F reading is independently corroborated: register 74 (ambient) tracked a separate outdoor sensor within 1–2°F across a 13 h run (61.8 vs 64.0, 60.0 vs 61.2 in the evening). Registers 74–78 are raw `U_WORD` with no scaling applied, so **1 count = 1°F** — which sets the resolution floor for anything derived from them (see the superheat caveat below).

The unit's temperature display mode can typically be changed in the settings menu. Whether this affects Modbus register values or only the display has not been verified — contributions from C° users welcome.

## Bus parameters

| Setting | Value |
|---|---|
| Mode | Modbus RTU |
| Baud rate | 9600 |
| Data bits | 8 |
| Parity | None |
| Stop bits | 1 |
| Device address | 0x01 |

## Read map (FC=03, holding registers)

### Control block (0x0300+)

| Register | Hex | Purpose | Values |
|---|---|---|---|
| 768 | 0x0300 | Cool setpoint | 47-83°F |
| 769 | 0x0301 | Heat setpoint | 47-104°F |
| 770 | 0x0302 | Upper bound (read-only) | typically 104 |
| 771 | 0x0303 | Lower bound (read-only) | typically 65 |
| 772 | 0x0304 | Mode | 0=Cool, 1=Heat, 8=Auto |
| 773 | 0x0305 | Power | 0=off, 1=on |
| 775 | 0x0307 | Energy mode | 0=Standard, 1=Boost, 2=Eco |
| 776 | 0x0308 | Version flag | 0x3B (always) |
| 779 | 0x030B | Auto setpoint | 47-104°F |
| 785 | 0x0311 | Running state echo | see below |

### Sensors (registers 29-98)

| Register | Purpose | Unit | Notes |
|---|---|---|---|
| 29 | Flow status | — | 255=flow present, 511=no flow. See fault section. |
| 64 | Compressor frequency | Hz | |
| 65 | Fan frequency | Hz | |
| 66 | EEV opening | steps | |
| 68 | **AC line voltage** | V | RMS mains. Measured over two full runs: idle mean 236.9V, running mean 237.3V — **no load-dependent rise**. Useful brownout / P8-P10 / P26 early warning. (An earlier revision of this document claimed reg 68 was post-PFC and rose under load. That was wrong; the PFC bus is reg 72.) |
| 69 | **AC input current** | ×0.1 A | Confirmed against an external power meter, 1499 samples: `VA = 0.09501 × (reg69 × reg68)`, r²=0.9702, vs `W = 22.09 × reg69`, r²=0.9594. Including line voltage improves the fit — the signature of a current, not a power. Measured scale 0.095 A/count vs nominal 0.1; see caveat below. |
| 70 | Compressor load index — **scale undecoded** | — | Hard-gated to 0 with the compressor. **Tracks compressor speed almost 1:1**: across a clean ramp on 2026-09-12, `reg70 = 1.072 x regHz + 12.3`, r2 = 0.968, with 42→78 Hz producing 60→96 counts. On top of that it drifts upward at *constant* speed as lift rises — 78 Hz held for eight hours on 2026-09-08 while reg 70 climbed 95→104 tracking condensing temperature, so the offset above speed runs ~13 early in a run and ~26 late. So `reg70 = f(speed) + g(lift)`, the signature of a load or torque index rather than a power measurement. Not a current in 0.1 A units: 96 implies 9.6 A against ~10.5 A of DC bus current at full speed, but at 42 Hz it predicts 3.8 A where the register says 6.0. Reliable as a boolean (non-zero = transferring heat). |
| 71 | **Condensing temp (high-side saturated)** | °F | Idle 78.7 (equalised between 88°F water and 74°F ambient); running mean 101, tracking outlet water +10–15°F approach **early in a run only** — see the 13 h capture below, where condensing held 94–97°F while outlet water climbed 78.8→90.5°F, so the approach decayed 16.9→4.2°F. Condensing temperature is pinned by the controller, not dragged up by water temperature; collapses 104→78 within 2 min of shutdown — refrigerant equalisation, not thermal mass. Medium-high confidence; not yet checked against a gauge set. |
| 72 | **DC bus voltage** | V | **Not an energy counter.** Idle 336 = √2 × 237Vac (passive rectified peak, PFC idle); running 377–380, tightly regulated (PFC boost active). On start dips to 327 (precharge inrush) then 357→378 within 5s; on stop returns to ~336 within 5s. Never accumulates, non-monotonic. Confirmed over a 13 h continuous run on 2026-09-14: **378.3 V flat for the entire run** (hourly means 378.2–378.3), dropping to 332.6 V at idle. The running value is regulated tightly enough that any drift is itself diagnostic. Direct readout for the P7 / P8 / P9 / P38 bus faults. |
| 74 | Ambient temp | °F | |
| 75 | Coiler temp (outdoor evaporator) | °F | |
| 76 | Incoiler temp (indoor heat exchanger) | °F | |
| 77 | Suction temp (refrigerant) | °F | |
| 78 | Discharge temp (refrigerant) | °F | |
| 79 | Water temp display (smoothed) | °F | Mirrors inlet; used by display for readout |
| 80 | **Outlet water temp** | °F | Confirmed against OEM display |
| 81 | Water tank sensor | signed | -58 = sensor not installed (E14, cosmetic) |
| 83 | State flag | — | Always 1 when powered; purpose unknown |
| 84 | **Inlet water temp** | °F | Confirmed against OEM display |

### Registers 272-275 — static constants

| Register | Value | Status |
|---|---|---|
| 272 | 998 | **Static.** Previously labelled "runtime counter" — it is not. Unchanged across 5 days of logging including a full 8.5h run. |
| 273 | 0 | Empty |
| 274 | 86 | **Static.** Previously labelled "low-side pressure" — it is not. |
| 275 | 90 | **Static.** Previously labelled "high-side pressure" — it is not. |

These almost certainly hold model/config constants. They are still polled
once a minute on the chance they move during an E05/E06 pressure fault,
which is the only condition under which they have not yet been observed.

### Caveat on the reg 69 current scale

Regressed against an external clamp meter the scale comes out **0.095 A per
count**, not the 0.1 that the register's granularity implies. That is a
systematic ~5% disagreement between the controller's own current sensing
and the reference meter, reproduced on two separate runs — it is not noise.
Which of the two is off has not been established. If you need absolute
current, calibrate against your own meter; if you need a relative load
signal, the register is excellent (r² > 0.97).

### Command and status block (registers 0-40)

Decoded 2026-09-10 by commanding a shutdown and a restart while logging at 5s
resolution. Every value here **leads** the physical event it describes — these
are command words, not measurements of what the machine is doing.

| Register | Purpose | Values |
|---|---|---|
| **0** | Status bitfield | `0x1000` (bit 12) = commanded to run; set/cleared within 5s of the on/off write, ~140s before the compressor moves. Also takes **`0x2008`** (bits 13+3) during the standby self-check described below — a different pattern with no relation to run demand. |
| **1** | Status bitfield | `0x20` (bit 5) = commanded to run, moving in lockstep with reg 0. Also takes **`0x04`** (bit 2) during the standby self-check. |
| **25** | Command bitfield | bit 6 `0x40` = run demand; bit 1 `0x02` = fan commanded. Idle `0`, dwell `0x40` (64), running `0x42` (66). |
| **26** | Command bitfield | bit 5 `0x20` = fan commanded; bit 0 `0x01` = compressor commanded. Idle `0`, fan only `0x20` (32), running `0x21` (33). |
| **30** | Static | 28 on this firmware. Did not move across a full stop/start cycle — despite the value, it is **not** a mirror of the 785 state echo. |
| **33** | Unknown | Reads `-1` (`0xFFFF`) almost always, but takes the value **3** for five minutes during the standby self-check — so it is **not** an unpopulated sensor input, despite the resting value. Read as signed. |
| **34** | Probably unpopulated sensor input | Reads `-1` (`0xFFFF`) constantly, including through the self-check. Same convention as reg 81's -58 for the absent tank sensor. Read as signed. |
| **36** | Static | 1. |
| **39** | **Compressor demand frequency** | Hz. The control law's output — what the controller *wants*. Steps directly to the new target. |
| **40** | **Ramp-limited frequency setpoint** | Hz. What is actually fed to the inverter. Rate-limited to **5 Hz per 5 s on deceleration**; on acceleration it steps straight to the demand and the drive's own ramp limits the actual. |

Reg 64 (compressor frequency) is the measured actual, which chases reg 40.
The three together are the full inverter control chain: **39 demand → 40 ramp →
64 actual**.

#### Observed shutdown sequence

`t=0` is the power-off write. Compressor was at 78 Hz.

```
+5.1  reg 0   4096 -> 0      demand cleared immediately
+5.1  reg 1     32 -> 0
+5.3  reg 39    78 -> 35     demand drops straight to the 35 Hz minimum
+5.3  reg 40    78 -> 74     ramp begins
      reg 40 then steps 74,69,64,59,54,49,44,39,35 at exactly 5.0s intervals
      reg 64 follows from just above: 77,76,72,64,60,56,52,44,40,36
+50.2 reg 39/40 35 -> 0
+55.1 reg 26    33 -> 32     compressor command bit clears
+55.3 reg 64    36 -> 0      compressor stops, 0.2s later
+141  fan 0                  84s post-run fan purge, then reg 25/26 -> 0
```

#### Observed startup sequence

`t=0` is the power-on write, after an 11.8 minute off period.

```
+4.1   reg 0/1   -> 4096/32   demand set, 140s before anything moves
+4.2   reg 25    -> 64        bit 6 run demand
+108.8 reg 785 34 -> 35       enters startup dwell
+124.1 reg 25 64 -> 66        bit 1 fan commanded
+124.1 reg 26  0 -> 32        bit 5 fan commanded
+129.3 fan       -> 22        fan spins, 5.2s AFTER the command bits
+139.2 reg 39/40 -> 42        demand and setpoint together, no ramp on the way up
+144.1 reg 26 32 -> 33        bit 0 compressor commanded
+144.4 reg 64    -> 30        compressor starts, 0.3s AFTER the bit
+154.3 reg 72 328 -> 347      PFC engages
+159.3 reg 72 347 -> 378      running bus voltage
+174..184 reg 64 30->34->38->42  actual climbs to demand
```

The restart delay is enforced between the demand bits being set and the fan
being commanded — roughly 120s here, within the 3-5 minute window the manual
describes.

**Why regs 0 and 1 matter most.** They are single bits set in otherwise-empty
16-bit words at the very bottom of the address space. That is the shape of a
status/fault bitmap, and it is the most promising place yet found for the
undecoded E-codes and the defrost flag. Bit 12 of reg 0 and bit 5 of reg 1 are
now known to mean "run demand"; the remaining 30 bits are unmapped because
this unit has not faulted.

### Sustained run: 13 hours, 2026-09-14

The longest continuous capture to date, and the only one that exercises the sensor
registers across their full working range. One uninterrupted heat call, 06:47→19:59
(13.19 h), water 73.4→86.7°F, ambient 60–70°F, 58.0 kWh at the meter. The compressor
sat at 82 Hz — its maximum — for all but the first and last half hour, so this is a
constant-speed sweep with only the lift changing.

| hour | outlet °F | reg 71 cond | approach | evap SH | reg 66 EEV | reg 72 bus | reg 69 |
|---|---|---|---|---|---|---|---|
| 06:30* | 74.5 | 81.3 | 8.3 | 9.8 | 153 | 352.4 | 96 |
| 07:00 | 78.8 | 95.9 | 16.9 | 2.4 | 178 | 378.3 | 195 |
| 09:00 | 81.5 | 95.0 | 13.6 | 1.5 | 163 | 378.3 | 196 |
| 11:00 | 83.9 | 94.7 | 10.8 | 1.3 | 152 | 378.3 | 198 |
| 13:00 | 86.5 | 97.0 | 10.2 | 0.9 | 151 | 378.3 | 201 |
| 15:00 | 88.5 | 97.6 | 9.2 | 1.0 | 149 | 378.3 | 192 |
| 17:00 | 89.5 | 95.6 | 6.0 | ~0 | — | 378.3 | 208 |
| 19:00 | 90.4 | 94.1 | 4.2 | ~0 | 285 | 377.9 | 208 |

\* 06:30 row is the ramp-up bucket — compressor still climbing to speed, PFC not yet
at its regulated value, superheat not yet pulled down.

Four things this establishes:

1. **Reg 72 is regulated, not merely "high while running."** 378.3 V held flat for
   thirteen hours. Combined with the 332.6 V idle reading this is the strongest
   confirmation yet that reg 72 is the PFC bus and not an energy accumulator.

2. **Condensing temperature is pinned, and the approach collapses.** Reg 71 stayed
   inside 94–97°F for the whole run while outlet water rose nearly 12°F beneath it.
   The approach therefore fell 16.9→4.2°F. This is the unit's capacity wall: heat
   transfer scales with that approach, so the water-temperature rise decayed from
   ~1.4°F/h to ~0.2°F/h even though input power was constant. Practical ceiling for
   this unit is condensing temperature minus a few degrees, i.e. low 90s°F.

3. **The EEV regulates discharge temperature, not suction superheat.** Reg 66 closed
   178→150 steps between 07:00 and 10:00 while discharge temperature climbed
   170→185°F — and then both stopped moving. Across 10:00–19:00 discharge held
   **183.3°F, sd 1.05** with the valve parked at 151 ± 2 steps. Discharge is the most
   tightly regulated quantity in the machine, by coefficient of variation:

   | quantity | CV over 10:00–19:00 |
   |---|---|
   | discharge temp | **0.57 %** |
   | condensing temp | 1.32 % |
   | ambient | 2.98 % |
   | evaporator coil | 3.48 % |

   That is the signature of a controller targeting discharge temperature: close the
   valve until discharge reaches setpoint, then hold, and let suction superheat land
   where it may. It makes engineering sense — discharge temperature is what damages a
   compressor, and it is measurable with a cheap surface sensor, whereas true suction
   superheat needs a pressure transducer this class of unit does not have. Liquid
   return is handled by the suction accumulator instead. 183°F discharge against 96°F
   condensing is healthy, and far too hot to be consistent with a flooded evaporator.
   The valve reopens to 285 steps during the shutdown ramp.

4. **Reg 69 rises with lift at constant speed.** Input current went 195→208 (×0.1 A)
   across the run, consistent with the reg 69 = current decode: same compressor speed,
   higher condensing pressure, more work. The trend is not monotonic — the 15:00 sample
   dips to 192 — because the controller trims speed slightly against its own setpoint,
   so this is a tendency across the run rather than a clean correlation.

> [!WARNING]
> **The derived "evaporator superheat" is unvalidated and probably is not superheat.**
> It is computed as reg 77 − reg 75. Closing an EEV must *raise* true suction
> superheat, yet across this run the valve closed 178→150 while the computed value
> fell. Both cannot be true. The likely explanation is that reg 75 does not read
> saturated evaporating temperature: if it sits at or near the evaporator outlet, or on
> a return bend already in the superheated region, then coil ≈ suction by construction
> and the 1–2°F difference is line pickup, not superheat. Consistent with that, reg 75
> and reg 77 track within 1–2°F for the entire run and never diverge.
>
> Resolution compounds it — both registers are integer °F, so the difference carries
> ±2°F and anything under ~2°F is indistinguishable from zero. **Do not read a small or
> negative value as evidence of flooding.** Confirming what reg 75 actually measures
> needs a gauge set: suction pressure gives the true saturation temperature. The same
> caution applies to the derived condenser approach, which depends on reg 71.

### Standby self-check (registers 0, 1, 2, 25, 33)

With the unit powered off, compressor and pump idle, the controller runs a
**five-minute routine** that briefly lights registers otherwise assumed dead.
Captured twice on 2026-09-12, identical in sequence and timing:

| offset | change |
|---|---|
| +0s | reg 1 → 4, reg 25 → 64 |
| +95s | reg 0 → 8200, reg 2 → 4 |
| +100s | reg 33 → 3 |
| +120s | reg 1 → 0 |
| +145s | reg 25 → 0 |
| +300s | reg 0 → 0, reg 2 → 0, reg 33 → -1 |

Observed at 03:33:02Z and 15:38:48Z — 12h05m apart, so probably a fixed
internal timer rather than anything tied to pump or heater state. Nothing
starts: the compressor never turns, the pump is unaffected, and the protection
bits stay at 1 throughout. Reg 25 bit 6 is the run-demand bit, asserted for two
minutes without any demand being acted on, which is what suggests a self-check —
plausibly the freeze-protection sampling these controllers run on a schedule.

**Reg 2 appears nowhere else.** It reads 0 in every other condition logged,
which is why earlier surveys of an idle machine listed it as empty.

This is the clearest illustration of why the v1.4.0 continuous capture exists.
Every earlier survey sampled a machine that was either idle or running steadily,
and this routine is invisible in both — it needs something watching during the
five minutes a day when it happens.

### Protection status registers (96-99)

These four registers form a protection status block. Pattern: **1 = OK, 0 = fault/protection active**.

| Register | Normal | Fault | Confirmed |
|---|---|---|---|
| 96 | 1 | TBD | TBD — candidate: high pressure (E05)? |
| 97 | 1 | TBD | TBD — candidate: low pressure (E06)? |
| **98** | **1** | **0** | **Water flow protection (E03) — confirmed by test** |
| 99 | 1 | TBD | TBD — candidate: phase fault (E01/E02)? |

Reg 98 flips to 0 whenever the flow switch is open — both when the unit is off (normal, no error) and when the unit is running without flow (E03 fault condition). The display and Tuya app apply context: reg 98 = 0 is only surfaced as E03 when the unit is powered on.

### Historical session log (registers 376-448)

This range updates at the **end of run cycles**, not in real-time. It appears to log the most recently completed heating session.

| Registers | Observed pattern | Hypothesis |
|---|---|---|
| 376-384 | Ascending temps (55→82°F) | Water temp at intervals during last heat-up |
| 385 | 1 | Boolean flag |
| 386 | ~200-240 | Possible session voltage or pressure reading |
| 387 | ~239 | Mirrors ambient voltage |
| 388 | ~133 | Possible session discharge temp snapshot |
| 391-398 | Mixed temps matching known sensors | Sensor snapshot at session end |
| 399 | 20 | Unknown |
| 400-403 | 70, 60, 50, 40 | Compressor frequency ramp-down log |
| 406-410 | ~42, 5, 41, 25, 27 | Operational parameters |
| 417-418 | 25, 27 | Unknown pair |
| 425-448 | Small values 5-45 | Possible COP or efficiency metrics per session |

### Efficiency/mirror log (registers 449-557)

Also updates at end of run cycles. Contains small values (1-9) and mirrors of operational data.

| Registers | Observed pattern | Hypothesis |
|---|---|---|
| 449-538 | Small values 1-9 | COP or efficiency metrics, one per historical session |
| 539-544 | 30, 30, 3, 9, 1, 30 | Operational parameters |
| 545-552 | Repeating pairs: 2, 54 | Possible delta T / flow rate pairs |
| 553-556 | Matches fan frequency | Fan frequency mirror (historical) |
| 557 | Matches compressor frequency | Compressor frequency mirror (historical) |

### Structured data (registers 2048-2063)

| Registers | Observed values | Hypothesis |
|---|---|---|
| 2048-2049 | 1, 1 | Firmware version or unit type ID |
| 2050-2053 | 7, 23, 30, 158 | Possible timestamp (month/day/min/sec?) |
| 2054-2057 | 9, 9, 9, 9 | Firmware sub-version |
| 2058-2059 | 0, 0 | Empty |
| 2060 | 104 | Mirrors upper setpoint bound |
| 2061 | 9 | Unknown |
| 2062 | 30 | Mirrors running state value |
| 2063 | 5 | Unknown |

### Empty ranges

The following register ranges consistently return 0 on this firmware:

- Registers 60-63, 67, 73, 82, 85-95
- Registers 100-164
- Registers 256-264, 266-269, 281-283, 295
- Registers 404-405, 411-416, 419-424
- Registers 2058-2059

Other firmware versions may use some of these ranges.

### Survey status

Ranges 0-59 and 786-800 were swept on 2026-09-10 with
`tools/register-survey.yaml`, across a commanded shutdown and restart. Results
are in the command/status block above. The bus answered cleanly throughout —
no Modbus exceptions — so these are real, implemented registers.

Of the 60 registers in 0-59, **thirteen** are live: 0, 1, 2, 25, 26, 29, 30,
33, 34, 36, 39, 40. In 786-800, only 786 (constant 26). Everything else reads
zero in every condition logged so far.

Reg 2 was only found once continuous capture was running - it is non-zero for
five minutes a day during the standby self-check and zero the rest of the time.

Since v1.4.0 the **production config captures 0-59 every cycle** as a single
frame, so the overlay is no longer needed for these ranges. Decoded registers
go to named sensors; every other non-zero value lands in the `Raw Register
Map` text sensor, which Home Assistant records only when it changes. Two
further sensors, `Last Defrost` and `Last Fault Snapshot`, latch the full map
plus surrounding conditions at the instant those events begin — a defrost
lasts minutes and then everything returns to normal, so the snapshot is what
makes the event legible afterwards.

Still never read: 165-255, 296-375, 558-767, 801-2047. No particular reason to
expect content there. `tools/register-survey.yaml` remains the tool for
sweeping them — edit `SURVEY_RANGES`.

**Coverage was never the bottleneck.** A register that does not change teaches
nothing, and this unit is healthy: 96/97/99 have read 1 continuously,
272/274/275 have never moved, no E-code has fired. The first sweep of an idle
machine returned a page of constants and looked empty; the same registers gave
up a complete inverter control chain the moment the unit was made to change
state. Any future decoding depends on catching **transitions**, and above all
a fault or a defrost cycle. Defrost needs the outdoor coil below freezing —
in a warm climate, a winter capture.

## Write operations

### Critical: the version flag

All FC=10 block writes to 0x0300 must end with `0x3B` in the 9th register (0x0308). Writes without this byte get silently ACK'd but ignored. This is presumed to be a firmware version validation byte.

### Write methods

| Operation | Function | Address | Notes |
|---|---|---|---|
| Power ON/OFF | FC=10 | 0x0300 (9 regs) | Set 0x0305 to 0 or 1, preserve all other fields |
| Mode → Cool | FC=06 | 0x0304 | Value 0x00 |
| Mode → Heat | FC=06 | 0x0304 | Value 0x01 |
| Mode → Auto | FC=06 | 0x0304 | Value 0x08 |
| Cool setpoint | FC=10 | 0x0300 (9 regs) | Set 0x0300 to new value |
| Heat setpoint | FC=10 | 0x0300 (9 regs) | Set 0x0301 to new value |
| Auto setpoint | FC=06 | 0x030B | Single register |
| Energy mode | FC=10 | 0x0300 (9 regs) | Set 0x0307 to 0/1/2 |

### Block write payload (9 registers starting at 0x0300)

```
CC HH UB LB MM PP 00 EE 3B
│  │  │  │  │  │  │  │  └─ Version flag (REQUIRED, always 0x3B)
│  │  │  │  │  │  │  └──── Energy mode
│  │  │  │  │  │  └─────── Reserved (0x00)
│  │  │  │  │  └────────── Power (0=off, 1=on)
│  │  │  │  └───────────── Mode (0=Cool, 1=Heat, 8=Auto)
│  │  │  └──────────────── Lower bound (0x41 / 65)
│  │  └─────────────────── Upper bound (0x68 / 104)
│  └────────────────────── Heat setpoint
└───────────────────────── Cool setpoint
```

To preserve other fields when changing one, **read the block first**, modify only the byte you want, and write the entire block back.

### Setpoint changes while unit is off

When power is off (0x0305 = 0), the controller silently ignores setpoint changes. Writes get ACK'd but values don't update. The included ESPHome config detects this via readback comparison and surfaces the failure in a "Last Error" text sensor.

## Flow status register (29)

Register 29 reports water flow switch state, encoded with a baseline:

| Value | Meaning | Context |
|---|---|---|
| 255 (0xFF) | Flow switch closed — water flowing | Normal |
| 511 (0x1FF) | Flow switch open — no water flow | Normal when unit is off; **E03 fault when unit is on** |
| Other | Potential E-code fault (TBD) | Being decoded; see contributions |

**Important:** 511 is not inherently a fault. The flow switch is open whenever no water is moving — including normal standby with pump off. The display and Tuya app only surface it as E03 when the unit is powered on and trying to run.

Register 98 provides a simpler boolean view of the same sensor: **1 = flow present, 0 = no flow**.

### Fault decode status

| Reg 29 value | E-code | Status |
|---|---|---|
| 255 (0xFF) | None | Normal |
| 511 (0x01FF) | **E03 Water Flow** | Confirmed by test |
| Other values | TBD | Log and contribute — see CONTRIBUTING.md |

Hypothesis: each additional E-code adds 0x100 to the baseline 0xFF (e.g. E05 high pressure may = 767, E06 low pressure = 1023). Unconfirmed until observed naturally.

## Register 785 (0x0311) — undecoded

Earlier revisions of this document mapped 785 to named operating states
(28 = equalization, 30 = ramping up, 32 = idle, 33 = running steady, and so on).
**That mapping is withdrawn.** It came from spotting values during a handful of
transitions; 599 samples across three days do not support it.

What the data does show:

- **It dithers between adjacent integers independently of machine state.** On
  2026-09-12 it alternated 30/31 across power-on, flow establishment, the
  compressor ramp from 0 to 78 Hz, and twenty minutes of steady running, with
  no change corresponding to any of them. That is a quantised measurement
  sitting near a boundary, not an enumerated state.
- Observed range **28-36**.
- Higher values *are* enriched for running: 36 appeared only with the
  compressor turning, while 29-31 are under-represented relative to the ~20%
  of samples in which the machine was running. So it carries some load-related
  information.
- Best single correlate is ambient temperature (r2 = 0.70 over 2.5 days), but
  the slope matches no unit conversion, and both drift with time of day - most
  likely confounded rather than causal.
- **Not a temperature.** Read as degC it misses every sensor we have by 7-19 degF
  on average with 6-12 degF of scatter: inlet water +12.3, outlet +8.6, ambient
  +18.7, incoiler +11.6, condensing +7.4.

Do not build logic on this register. Compressor frequency (reg 64), the command
bitfields (0, 1, 25, 26) and the demand/setpoint pair (39, 40) between them
describe operating state unambiguously and are decoded.

Both the original mapping and a later amendment to it (reclassifying 35 from
"cool mode related" to "heat-mode startup dwell") were made from single
observations. 35 in fact appears 65% of the time while running and 33% while
stopped. Small samples of a machine that spends most of its life in one state
produce confident-looking mappings that mean nothing.

## Defrost mode — not yet identified

The Tuya app displays a "Defrosting" status when the unit runs a defrost cycle (reversing refrigerant flow briefly to clear ice from the outdoor evaporator coil — happens periodically during heat operation in cool ambient conditions). The OEM display likely shows it as well.

**We have not yet identified the register that reports defrost state.** Possibilities:

- An additional bit in 0x0311 (state echo)
- A separate flag register we haven't surveyed
- Encoded into one of the unknown registers (68, 69, 71, 83)
- Inferred by the Tuya WiFi module from refrigerant temperature patterns rather than a dedicated register

To find it, watch the diagnostic register dumps during a defrost event. Defrost is typically characterized by:

- Fan stopping (fan freq → 0) while compressor continues
- Coiler temp rising (outdoor coil being heated)
- Brief reversal of inlet/outlet water delta T
- The Tuya app showing "Defrosting"

**Since v1.4.0 this is instrumented.** The `Defrosting` binary sensor infers
the cycle from the physical signature — compressor turning while the outdoor
fan is stopped, heat mode only — without needing a register at all. In every
run logged, the fan has never been at zero while the compressor turns, so the
combination is unambiguous. When it fires, `Last Defrost` latches the
compressor, fan, coil, ambient, suction, discharge and condensing
temperatures, the EEV position, **and the full 0-59 register map**, and logs
the lot at WARN.

So the real defrost flag, if one exists, will identify itself the first time
the unit defrosts: compare the latched register map against the healthy
baseline documented in the command block above. In a warm climate that means
waiting for winter — the outdoor coil has to be below freezing.

If you capture a defrost event and identify which register changes, please contribute the finding back — see [CONTRIBUTING.md](../CONTRIBUTING.md).

## OEM fault code reference

The following fault codes come directly from the Aquastrong HEX 75 OEM manual. These are the codes displayed on the unit's front panel and in the Tuya app. The relationship between these display codes and the numeric value in Modbus register 29 is not yet fully decoded — contributions welcome.

### E-series faults (main board / system)

| Code | Fault | Notes |
|---|---|---|
| E01 | Wrong phase fault | Power supply connected wrong phase |
| E02 | Out of phase fault | Power supply missing phase |
| **E03** | **Water flow switch fault** | **Confirmed: reg 29 = 511, reg 98 = 0** |
| E04 | Main board and 4G module communication fault | |
| E05 | High pressure switch protection | High-voltage switch, refrigerant, fan, or scale in heat exchanger |
| E06 | Low pressure switch protection | Low-voltage switch, refrigerant, or fan fault |
| E09 | Line controller and motherboard communication failure | |
| E11 | Time limit protection | Trial period expired |
| E12 | Exhaust gas temperature too high fault | Fluorine system clog, refrigerant, or sensor |
| E14 | Hot water tank temperature failure | Sensor loose, damaged, or motherboard port |
| E15 | Water inlet temperature sensor failure | Sensor loose, damaged, or motherboard port |
| E16 | Coil sensor failure | Sensor loose, damaged, or motherboard port |
| E18 | Exhaust gas sensor failure | Sensor loose, damaged, or motherboard port |
| E21 | Environmental sensor failure | Sensor loose, damaged, or motherboard port |
| E22 | User return water sensor failure | Sensor loose, damaged, or motherboard port |
| E23 | Cooling subcooling protection | Normal anti-freeze protection |
| E27 | Out of the water sensor failure | Sensor loose, damaged, or motherboard port |
| E29 | Return gas sensor failure | Same as above |
| E33 | High pressure sensor failure | Same as above |
| E34 | Low pressure sensor failure | Same as above |
| E37 | Inlet and outlet water temperature difference too large | Water inlet/outlet sensor damaged or misplaced, or insufficient flow |
| E38 | DC fan 1 failure | Fan driver board or motor failure |
| E39 | DC fan 2 failure | Fan driver board or motor failure |
| E42 | Cooling coil sensor 1 failure | Sensor loose, damaged, or motherboard port |
| E47 | Economizer inlet sensor failure | Same as above |
| E49 | Economizer outlet sensor failure | Same as above |
| E51 | High pressure over high protection | Same as E05 |
| E52 | Low pressure over low protection | Same as E06 |
| E55 | Expansion board communication failure | Signal wire, expansion board, or motherboard |
| E80 | Power supply error | Single-phase unit detecting three-phase signal |
| E88/E89 | Abnormal communication with main control board | Replace main board, drive module; separate power cable layout |
| E94 | Water pump feedback failure | Pump drive board or water pump failure |
| E96 | Press 1 driver and main control board communication abnormal | Signal wire, motherboard, or drive board |
| E98 | Fan 1 driver and main control board communication abnormal | Signal wire, motherboard, or fan drive board |
| E99 | Fan 2 driver and main control board communication abnormal | Same as above |
| EA1 | Network model error | Different series units cannot be cascaded |

### P-series faults (driver board / inverter)

| Code | Fault | Notes |
|---|---|---|
| P1 | IPM overcurrent / IPM module protection | Check compressor line sequence; change driver board |
| P2 | Compressor drive failure | Same as P1 |
| P3 | BIt0: Compressor overcurrent alarm | Check incoming voltage |
| P4 | Input voltage out of phase | Same as P1 |
| P5 | IPM current sampling failure | Driver board problem |
| P6 | Power component overheating shutdown | Driver board problem |
| P7 | Pre-charge failure | Check incoming voltage |
| P8 | DC bus over-voltage | Check incoming voltage |
| P9 | DC bus under-voltage | Check incoming voltage |
| P10 | AC input under-voltage | Change driver board |
| P11 | AC input overcurrent | Change driver board |
| P12 | Input voltage sampling fault | DSP chip problem, change driver board |
| P13 | DSP and PFC communication fault | DSP chip problem, change driver board |
| P14 | Heat sink temperature sensor failure | Reconnect/replace temp sensor or main board |
| P15 | Communication failure between DSP and communication board | DSP chip problem, change driver board |
| P16 | Abnormal communication with main control board | Replace main board or drive module; separate power cables |
| P17 | Compressor over current alarm | Change driver board |
| P18 | Compressor weak magnetic protection alarm | Replace compressor |
| P19 | PIM overheat alarm | Same as P1 |
| P20 | PFC overheat alarm | Change driver board |
| P21 | AC input overcurrent alarm | Check incoming voltage |
| P22 | EEPROM failure alarm | Driver board problem |
| P24 | EEPROM refresh completed | Driver board problem |
| P25 | Temperature sensing fault frequency limit | Reconnect/replace temp sensor or main board |
| P26 | AC undervoltage frequency limit protection alarm | Check incoming voltage |
| P33 | IPM module overheating shutdown | Same as P1 |
| P34 | Compressor out of phase | Same as P1 |
| P35 | Compressor overload | Same as P1 |
| P36 | Input current sampling fault | Same as P1 |
| P37 | PIM supply voltage failure | Same as P1 |
| P38 | Precharge circuit voltage failure | Driver board problem |
| P39 | EEPROM fault | Driver board problem |
| P40 | AC input overvoltage fault | Same as P1 |
| P41 | Microelectronics fault | Driver board problem |
| P42 | Compressor type code fault | Driver board problem |
| P43 | Current sampling signal overcurrent | Same as P1 |

> **Note on reg 81 = -58:** Register 81 returns a large negative number on this unit. This corresponds to **E14 (Hot water tank temperature sensor failure)** — the sensor is simply not installed on this model. The Tuya app reports it as "Water Tank Temp Sensor Fault." It is a cosmetic/persistent fault that does not affect operation and can be ignored.

### Fault behavior

- Faults are **non-latching**: they clear automatically when the condition resolves
- After a fault clears, the compressor enforces a 3-5 minute restart delay (independent of the fault state)
- The fault code register (reg 29) and flow boolean (reg 98) update every poll cycle

## Setpoint ranges

These come from the Tuya app spec, validated by observation:

| Mode | Min | Max |
|---|---|---|
| Cool | 47°F | 83°F |
| Heat | 47°F | 104°F |
| Auto | 47°F | 104°F |

The controller may reject values outside these ranges. The provided ESPHome config enforces them on the HA side.

## Polling rate

The OEM display polls multiple register ranges every ~200ms. The included ESPHome config polls every 2 seconds, which is more than enough for HA-level control and reduces bus traffic.

## Why dual-bus?

The controller does **not** handle two Modbus masters on the same bus. Attempting to share COM4 with the display produces:

- ~17 CRC errors per second (vs ~1-3 from EMI alone)
- Zero successful reads in some periods
- Spurious fault codes from the controller misinterpreting collided frames

COM2 is a separate physical bus to the same controller. Using it for the ESP allows the display to remain fully functional on COM4.

## ESPHome 2026.3.0+ transmit arbitration (critical)

ESPHome 2026.3.0 rewrote the `modbus` component's transmit gating.
Before 2026.3.0, the component transmitted unconditionally. From
2026.3.0 on, it refuses to transmit until the RS-485 line has been
idle for `frame_delay + turnaround_time` after **any** received byte
(`Modbus::tx_blocked()`, conditions 1-5).

With the default `turnaround_time: 100ms`, stray bytes arriving at
just ~10/second block transmission **permanently**. Compressor VFD
noise on this hardware exceeds that easily, producing a deadlock: the
ESP cannot deliver a power-off command while the compressor generates
the noise that blocks it. Observed in the field as 90+ seconds with
zero transmitted frames ("...ms after last send" counting up in logs)
while commands sat queued.

**Required setting** (in `config/pool-heatpump.yaml` since v1.2.0):

```yaml
modbus:
  turnaround_time: 5ms
```

This shrinks the post-receive blackout to ~9ms (frame delay ~4ms at
9600 baud + 5ms). Noise then needs sustained sub-9ms gaps to starve
transmission, restoring approximately the pre-2026.3 talk-over-noise
behavior. The `command_throttle` on the controller already paces this
single-slave bus, so the turnaround delay serves no purpose here.

Symptoms if you hit this: all sensors stop updating while the
compressor runs, writes are silently lost, logs show repeated
"Clearing buffer" / "CRC check failed" warnings with the
"after last send" timer growing unboundedly, and the device never
reports offline (retries only count on transmitted frames — starved
commands are never sent, so the retry counter never moves).

### Frame count guidance

Bus time is dominated by per-frame throttle slots, not data bytes. A
A 21-register read costs one `command_throttle` slot — the same as a
1-register read. Modbus allows up to **125 registers per read**, so a wide
contiguous block is nearly free while a scattered handful is not. When adding
sensors, pad gaps with `internal: true` sensors so contiguous blocks read as
single frames.

The v1.4.0 config reads, per 5s cycle:

| Frame | Registers |
|---|---|
| 1 | 0-59 (the whole command block, one frame) |
| 2 | 64-84 |
| 3 | 96-99 |
| 4 | 768-779 |
| 5 | 785 |
| 6 | 29 |

plus 272-275 and 786-800 every 12th cycle. Six frames at 100ms throttle is
600ms of a 5000ms cycle.

Capturing all sixty registers of the command block therefore costs about what
a single register costs. That is the whole reason the v1.4.0 event capture is
affordable: there is no cheaper way to be watching when a fault or a defrost
finally happens than to read the entire block every cycle.

## Validation methodology

Each register's purpose was validated by:

1. Snooping the display ↔ controller traffic with a logic analyzer / passive listener
2. Correlating writes to user actions (pressing buttons, changing setpoints)
3. Reading the controller's response and matching against expected behavior
4. Cross-checking sensor values against the display's labeled readout (the display's "Query" / parameter view screen)
5. Deliberate fault induction (flow switch test) to confirm protection register behavior
