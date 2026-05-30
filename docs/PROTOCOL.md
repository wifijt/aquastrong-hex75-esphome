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
| 785 | 0x0311 | Running state echo | 0x20 idle, 0x21+ running |

### Sensors (60-95)

| Register | Purpose | Unit |
|---|---|---|
| 29 | Fault code bitfield | see below |
| 64 | Compressor frequency | Hz |
| 65 | Fan frequency | Hz |
| 66 | EEV opening | steps |
| 70 | Active heating indicator | non-zero when actively heating |
| 72 | Energy total | ×0.01 kWh |
| 74 | Ambient temp | °F |
| 75 | Coiler temp (outdoor evaporator) | °F |
| 76 | Incoiler temp (indoor heat exchanger) | °F |
| 77 | Suction temp (refrigerant) | °F |
| 78 | Discharge temp (refrigerant) | °F |
| 79 | Water temp display (smoothed) | °F |
| 80 | **Outlet water temp** | °F |
| 81 | Water tank sensor | signed; -58 = sensor not installed |
| 84 | **Inlet water temp** | °F |

### Unknown/TBD registers

These return non-zero values but their function isn't fully decoded:

| Register | Observed values | Hypothesis |
|---|---|---|
| 68 | 233-241 (stable) | Possibly a pressure reading or status code |
| 69 | 8-189 (varies with load) | Refrigerant high-side metric |
| 71 | 71-95 (varies with load) | Refrigerant temp at another point |
| 83 | always 1 when powered | State flag (purpose unknown) |

PRs to identify these welcome.

### Empty range

Registers 100-149 are present but consistently return 0 on this firmware. Other firmware versions may use this range.

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

## Fault code register (29) — bitfield

The fault code register is a bitfield, not a single fault code. Baseline value with no faults active is `255` (0xFF) — all eight low bits set is the "normal" pattern.

| Fault | Bit | Mask | Composite value (with 0xFF baseline) |
|---|---|---|---|
| Water Flow Protection | 8 | 0x0100 | 511 (0x01FF) |
| Others | TBD | TBD | TBD |

Only the Water Flow bit has been definitively decoded by observation. The full set of fault conditions the controller can report is documented in the OEM manual (see table below) — cross-referencing these against observed register values will complete the map over time.

## OEM fault code reference

The following fault codes come directly from the Aquastrong HEX 75 OEM manual. These are the codes displayed on the unit's front panel and in the Tuya app. The relationship between these display codes and the numeric value in Modbus register 29 is not yet fully decoded — contributions welcome.

### E-series faults (main board / system)

| Code | Fault | Notes |
|---|---|---|
| E01 | Wrong phase fault | Power supply connected wrong phase |
| E02 | Out of phase fault | Power supply missing phase |
| **E03** | **Water flow switch fault** | **Confirmed: triggers reg 29 bit 0x100 (value 511)** |
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

### Fault register decode status

| Observed reg 29 value | Confirmed E-code | Notes |
|---|---|---|
| 255 (0xFF) | None | Normal operating state, no faults |
| 511 (0x01FF) | **E03** | Water flow switch fault — confirmed by test |
| Others | TBD | Contributions welcome — see CONTRIBUTING.md |

> **Note on reg 81 = -58:** Register 81 returns a large negative number on this unit. This corresponds to **E14 (Hot water tank temperature sensor failure)** — the sensor is simply not installed on this model. The Tuya app reports it as "Water Tank Temp Sensor Fault." It is a cosmetic/persistent fault that does not affect operation and can be ignored.

### Fault behavior

- Faults are **non-latching**: they clear automatically when the condition resolves
- After a fault clears, the compressor enforces a 3-5 minute restart delay (independent of the fault state)
- The fault code register updates every poll cycle



## State echo register (0x0311)

The 0x0311 register reflects current operational state:

| Value | Meaning |
|---|---|
| 0x20 | Idle (power on, no compressor) |
| 0x21 | Running (heat) |
| 0x22 | Transitional / cool-related |
| 0x23 | Cool-related (compressor running) |

Not strictly necessary for control — useful for monitoring.

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

The mapping is high confidence for everything documented above; the unknown registers (68, 69, 71, 83) are simply waiting for more observation.
