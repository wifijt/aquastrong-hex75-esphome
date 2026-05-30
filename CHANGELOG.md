# Changelog

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
