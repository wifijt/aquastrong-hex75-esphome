# Modbus Protocol Reference

This is the reverse-engineered Modbus RTU protocol for the CHICO SMBPRO53 V1.44 controller (PCB marked **`R-SY013-BP`**) as found in the Aquastrong HEX 75. It's likely substantially the same across the OEM family (Fairland, IPS, Poolsystems, Aquark) but exact compatibility is unconfirmed.

If your controller PCB is marked `R-SY013-BP`, this protocol map should apply directly. Similar boards from the same OEM may use the same protocol with minor variations.

## Temperature units

**This integration was developed on a unit configured to report in °F.** All setpoint registers and temperature sensors return values in °F natively — no conversion is applied in the ESPHome config.

If your unit is configured for °C, it presumably reports all temperature registers in °C instead. In that case:
- Update `unit_of_measurement: "°F"` to `unit_of_measurement: "°C"` on all temperature sensors in the YAML
- Update the setpoint ranges in the `number:` entities accordingly (47-83°F → ~8-28°C for Cool, etc.)

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
| 68 | AC input voltage | V | Stable ~239-244V; hypothesis confirmed by voltage sag when compressor stops |
| 69 | Compressor load metric | — | Scales ~1.5-1.7× compressor Hz; hypothesis = input current ×0.1A |
| 70 | Active heating indicator | — | Non-zero when compressor running and heat transferring; mirrors compressor load |
| 71 | Refrigerant temp | — | Varies with compressor load; point in refrigerant circuit TBD |
| 72 | Energy total | ×0.01 kWh | |
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

## State echo register (0x0311)

The 0x0311 register (decimal 785) reflects current operational state:

| Value | Hex | Conditions observed |
|---|---|---|
| 28 | 0x1C | Post-shutdown equalization (compressor off, EEV equalizing) |
| 29 | 0x1D | Protection mode, startup dwell, or running at low-mid load |
| 30 | 0x1E | Ramping up (compressor spinning up) |
| 32 | 0x20 | Idle (powered on, compressor off, flow present) |
| 33 | 0x21 | Running steady — heat mode (higher load) |
| 34 | 0x22 | Transitional |
| 35 | 0x23 | Cool mode related |

**Note:** 0x1D is used across multiple states — protection mode, startup dwell, and normal running at low load. It is **not reliable as a fault indicator** on its own. Combine with reg 29 and compressor frequency for full state assessment.

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

If you capture a defrost event with this integration and identify which register changes, please contribute the finding back — see [CONTRIBUTING.md](../CONTRIBUTING.md).

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

## Validation methodology

Each register's purpose was validated by:

1. Snooping the display ↔ controller traffic with a logic analyzer / passive listener
2. Correlating writes to user actions (pressing buttons, changing setpoints)
3. Reading the controller's response and matching against expected behavior
4. Cross-checking sensor values against the display's labeled readout (the display's "Query" / parameter view screen)
5. Deliberate fault induction (flow switch test) to confirm protection register behavior
