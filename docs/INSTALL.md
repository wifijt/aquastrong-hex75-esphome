# Installation Guide

## Prerequisites

- Home Assistant running on your network
- ESPHome installed (either as HA add-on, standalone Docker, or CLI)
- Physical access to the Aquastrong HEX 75 controller's COM2 terminal
- Basic familiarity with crimping/wiring small-gauge cable

## Step 1: Hardware install

See [HARDWARE.md](HARDWARE.md) for the parts list and wiring diagram.

**Quick summary:**
1. Power down the heat pump at the breaker
2. Open the top cover and open the electrical compartment to expose the controller board
3. Connect MAX485 module's A/B to the controller's COM2 screw terminal block
4. Wire MAX485 to ESP32-C6:
   - VCC → 3.3V or 5V (match module variant)
   - GND → GND
   - RO → GPIO5
   - DI → GPIO4
5. Mount the ESP somewhere clean (preferably outside the heat pump enclosure)
6. Power up the heat pump and confirm the OEM display still works normally

## Step 2: Prepare ESPHome config

1. Copy [`config/pool-heatpump.yaml`](../config/pool-heatpump.yaml) to your ESPHome config directory
2. Create or edit your `secrets.yaml`:

   ```yaml
   wifi_ssid: "your_wifi_network"
   wifi_password: "your_wifi_password"
   api_encryption_key: "generate_a_32_byte_base64_key"
   ota_password: "any_password_you_like"
   ```

   Generate `api_encryption_key` with `openssl rand -base64 32` or use the ESPHome dashboard's built-in tool.

3. Adjust the device name if you want something other than `pool-heatpump`:

   ```yaml
   esphome:
     name: pool-heatpump          # ← change here
     friendly_name: Pool Heat Pump # ← change here
   ```

## Step 3: Initial flash

The first flash must be done over USB:

```bash
esphome run pool-heatpump.yaml
```

Or via the ESPHome dashboard's "Install" → "Plug into the computer running ESPHome Dashboard".

After the first flash, future updates can be done OTA (wireless).

## Step 4: Add to Home Assistant

ESPHome devices auto-discover. Within a few seconds of the ESP coming online, Home Assistant will show a notification to add the device. Click through, enter the API encryption key when prompted, and the entities will appear.

## Step 5: Verify

Open Home Assistant → Settings → Devices & Services → ESPHome → `pool-heatpump`. You should see:

**Sensors** (numeric):
- Pool Heater Ambient Temp
- Pool Heater Coiler Temp
- Pool Heater Compressor Frequency
- Pool Heater Discharge Temp
- Pool Heater EEV Opening
- Pool Heater Energy Total
- Pool Heater Fan Frequency
- Pool Heater Fault Code
- Pool Heater Incoiler Temp
- Pool Heater Inlet Water Temp
- Pool Heater Outlet Water Temp
- Pool Heater Suction Temp
- Pool Heater Active Heating
- Pool Heater Water Temp (display)

**Binary sensors**:
- Pool Heater Fault Active
- Pool Heater Water Flow Fault
- Pool Heater Heating Active

**Controls**:
- Pool Heater Power (switch)
- Pool Heater Mode (select: Cool/Heat/Auto)
- Pool Heater Energy Mode (select: Standard/Boost/Eco)
- Pool Heater Cool Setpoint (number)
- Pool Heater Heat Setpoint (number)
- Pool Heater Auto Setpoint (number)

**Text sensor**:
- Pool Heater Last Error

## Smoke test

Recommended first interactions, in order:

1. **Check sensors are populating** — ambient temp, water temps, etc. should have real values within 5-10 seconds. If they show "unavailable" or stay blank, check the ESPHome logs for CRC errors.

2. **Toggle Energy Mode** (lowest-stakes write) — set it from Standard → Boost. Watch HA: should sit at Standard for 2-3 seconds, then flip to Boost when confirmed. The OEM display should also show "Boost" within the same window. Set it back to Standard.

3. **Toggle Power off then on** — same expected behavior. Confirmation via readback.

4. **Change Heat setpoint** — set to your normal target. The display should show the new value within 5 seconds.

If any of these don't confirm within 10 seconds, check the **Pool Heater Last Error** text sensor — it'll have a description of what went wrong.

## Troubleshooting

### "All sensors show unavailable"

- ESP isn't reaching the controller. Check A/B aren't swapped, MAX485 is powered.
- Check ESPHome logs for CRC errors. A few per minute is normal; constant errors mean something's wrong with wiring.

### "Sensors work but writes don't confirm"

- Most likely: the OEM display is still connected to COM2 instead of COM4, or you accidentally connected to COM4. Verify which port the ESP is on.
- Less likely: a different firmware variant of the CHICO board. Open an issue with logs.

### "Setpoint changes silently fail"

- Check if the unit is OFF. The controller rejects setpoint writes while powered off. Turn it on first, then change setpoints.

### "Constant CRC errors during operation"

- Compressor/fan EMI coupling into the RS-485 cable. See HARDWARE.md for noise mitigation: twisted pair, shielded cable, ferrite bead, cable routing.

### "HA shows wrong state at boot"

- The included config has idle-state sync that publishes the controller's actual values to HA every poll. If HA is showing stale defaults, watch for 1-2 poll cycles (~5 seconds) for it to update.

