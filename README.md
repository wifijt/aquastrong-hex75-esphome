# Aquastrong HEX 75 — ESPHome / Home Assistant Integration

Local control of Aquastrong HEX 75 (and likely other CHICO-controlled) pool heat pumps over RS-485 Modbus using ESPHome, with no cloud dependency.

This project replaces the Tuya cloud integration with a fully local, fully controllable Home Assistant integration. The OEM display and Tuya WiFi remain functional alongside ESPHome.

## What you get

- **Full local control**: power, mode (Cool/Heat/Auto), all three setpoints, energy mode (Standard/Boost/Eco)
- **Complete sensor visibility**: water inlet/outlet, refrigerant circuit, compressor and fan frequencies, EEV opening, energy usage
- **Fault detection**: water flow protection and other faults exposed as binary sensors
- **No cloud required**: Tuya can be left disabled or removed entirely
- **Coexists with the OEM display and Tuya app**: three independent control surfaces stay in sync

## Compatible hardware

This integration was developed and tested on:

- **Heat pump**: Aquastrong HEX 75
- **Controller**: CHICO SMBPRO53 V1.44
- **PCB**: **R-SY013-BP** (printed on the board)

The CHICO board is an OEM platform shared across several brands. **If your unit's controller PCB is marked `R-SY013-BP`, this integration should work directly.** If it's a similar board with a different revision number, it's likely close — possibly with minor register adjustments.

Brands known to use CHICO-family controllers:

- Aquastrong
- Fairland
- IPS (Inverter Pool Systems)
- Poolsystems
- Aquark

If you have a CHICO board with the same dual COM port layout, this should be a strong starting point.

## How it works

The heat pump exposes several RS-485 ports on the controller these are the ones identified:

| Port | Original use | What we use it for |
|------|-------------|---------------------|
| COM4 | Touchscreen display (JST connector) | Display stays here, untouched |
| COM2 | Auxiliary terminal block | ESP32 connects here for read/write |

![Control board overview](images/control_board.jpeg)
*The CHICO R-SY013-BP control board. The PCB part number is visible near the bottom center. The green screw terminal block (COM2) is at the bottom edge.*

Using separate ports for the ESP32 and the display means **no bus contention**. Both can operate simultaneously and stay in sync.

The Tuya WiFi module reports state to the cloud independently — if you want to keep the Tuya app working alongside HA, you can. If not, you can disable the WiFi module.

```
┌─────────────────┐                ┌──────────────────┐
│ Tuya WiFi       │── cloud ─────▶│  Tuya Mobile App │
│ (independent)   │                └──────────────────┘
├─────────────────┤
│ CHICO           │── COM4 ──────▶ Tuya module / Display (touch UI)
│ Controller      │
│ SMBPRO53        │── COM2 ──────▶ ESP32 (ESPHome) ──▶ Home Assistant
└─────────────────┘
```

## Quick start

1. **Hardware** — see [docs/HARDWARE.md](docs/HARDWARE.md) for the parts list and wiring
2. **Protocol reference** — see [docs/PROTOCOL.md](docs/PROTOCOL.md) for the Modbus map (useful if you need to adapt to a slightly different unit)
3. **Install ESPHome config** — copy [config/pool-heatpump.yaml](config/pool-heatpump.yaml) and edit your WiFi/API credentials in `secrets.yaml`
4. **Flash and verify** — see [docs/INSTALL.md](docs/INSTALL.md) for the full procedure
5. **Optional dashboard examples** — see [examples/](examples/) for Lovelace cards and automations

## Status

| Area | State |
|---|---|
| Read sensors | ✅ Production |
| Write controls | ✅ Production with confirmation/retry |
| Fault detection | ✅ Water flow confirmed, others TBD |
| Defrost mode detection | ❌ Not yet identified (see PROTOCOL.md) |
| Dual-bus isolation | ✅ Tested and working |
| Documentation | 🚧 Initial release |

## Known limitations

- This is an **independent project**, not affiliated with Aquastrong, Fairland, or any OEM
- Register addresses were reverse-engineered from snooping the display ↔ controller protocol; firmware updates may change them
- Some registers' purposes are still unknown — see [PROTOCOL.md](docs/PROTOCOL.md) for what's known
- Modifies hardware: requires opening the unit and adding wiring to the auxiliary RS-485 port — **understand your warranty implications**

## Acknowledgements

This work was done by reverse-engineering the Modbus protocol between the CHICO controller and its display, then validating each register against the display's labeled readouts. **No proprietary documentation was used.**

## Disclaimer
This is an independent community project and is not affiliated with, endorsed by, or supported by Aquastrong, Fairland, CHICO, or any related manufacturer or distributor.
The Modbus protocol described here was reverse-engineered by observing communication between the controller and its display. No proprietary documentation was used. Register mappings may change with firmware updates without notice.
This project involves opening electrical equipment and adding wiring inside an appliance that operates at high voltage. Working inside the unit carries risk of electric shock, equipment damage, and may void your warranty. Only proceed if you are comfortable working with electrical equipment and understand the risks. **The authors accept no liability for damaged equipment, personal injury, voided warranties, or any other consequences arising from the use of this project.
Use at your own risk.**

## License

MIT — see [LICENSE](LICENSE). Use at your own risk. The author accepts no responsibility for damaged heat pumps, voided warranties, or unhappy party guests resulting from pool water at the wrong temperature.

## Contributing

PRs welcome. Especially valuable:

- **Confirmed compatibility** with other CHICO-based units (Fairland, IPS, etc.)
- **Defrost mode detection** — the Tuya app shows a "Defrosting" status but the register hasn't been identified yet
- **Additional fault code bits** decoded
- **Improved register identification** for unknowns (regs 68, 69, 71, 83)
- **Lovelace dashboards** and HA automations
