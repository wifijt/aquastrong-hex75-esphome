# Contributing

Contributions welcome! Most valuable areas:

## Confirmed compatibility

If you own a CHICO-based pool heat pump from any brand and have tested this integration, please open an issue or PR documenting:

- Brand and model
- Controller firmware label (e.g. SMBPRO53 V1.44)
- **PCB silkscreen marking** (e.g. `R-SY013-BP`) — this is the most useful identifier for matching
- Which registers worked as documented
- Any registers that needed adjustment
- Photos of the controller board if possible

This helps us build the compatibility matrix.

## Register identification

Several registers are documented as "unknown" in [docs/PROTOCOL.md](docs/PROTOCOL.md):

- Reg 68 (stable around 233-241)
- Reg 69 (varies with load)
- Reg 71 (varies with load)
- Reg 83 (always 1 when powered)

If you can correlate any of these with documented values from your unit's service menu or display, please contribute findings.

## Defrost mode detection

The Tuya app shows a "Defrosting" status when the unit runs an automatic defrost cycle, but we haven't yet identified which register reports this state. If you catch your unit defrosting:

1. Note the time
2. Look at all the diagnostic registers (especially in `http://pool-heatpump.local/`) during the defrost window
3. Compare against a normal-operation baseline
4. Report whatever changes — it could be:
   - A new bit in register 0x0311 (state echo)
   - A flag in one of the currently-unknown registers (68, 69, 71, 83)
   - A register we haven't scanned yet

Defrost cycles typically show: fan stopping (fan freq → 0) while the compressor continues, coiler temp rising, and the Tuya app showing "Defrosting" simultaneously.

## Additional fault code bits

The OEM manual fault code table is now included in [docs/PROTOCOL.md](docs/PROTOCOL.md). Only E03 (Water Flow, reg 29 value 511) has been confirmed against the Modbus register. All other E-codes and P-codes from the manual are documented but their Modbus register 29 bit mappings are unknown.

If you encounter any fault condition and can capture the reg 29 value at the time, please share — even a single data point helps complete the decode table.

## Dashboard examples

If you've built a nice HA dashboard, Lovelace card, or automation for this integration, PRs to `examples/` welcome.

## Code style

- ESPHome YAML: keep formatting consistent with the existing config
- Comments encouraged, especially for non-obvious lambdas
- Test changes on real hardware before submitting

## Issue templates

When reporting issues, please include:

- ESPHome version
- Heat pump model and controller version
- Relevant ESPHome log output (especially any CRC errors or "rejected" messages)
- What you expected vs what happened

## Code of conduct

Be kind, be patient, be specific. We're all just trying to keep our pools at the right temperature.
