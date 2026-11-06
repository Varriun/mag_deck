# mag_deck v2

A split, foldable-phone gaming controller: top module with a MagSafe-style ring and BLE MCU, bottom module with buttons, triggers, and dual capacitive trackpads (Steam Controller-inspired). Slides onto/off the phone.

> This README replaces an earlier leftover template (previously described an unrelated nRF52840/ESB project — content was stale and has been rewritten to reflect mag_deck v2's actual status as of 2026-08-09).

---

## Current status: architecture + component selection locked, PCB design not started

This is a progress log, kept current as decisions get made. Pick up from "Next steps" below.

---

## Key architecture decisions

**1. No FPGA in the shipped product.**
The SystemVerilog RTL in `Hardware Verilog/` (debounce, I2C master, input mapper, tx encoder, UART TX) was originally written for FPGA/Tiny Tapeout ASIC submission. Reviewed against the actual product requirements: none of it is timing-critical or parallel enough to justify dedicated fabric — it's textbook MCU-peripheral territory (GPIO debounce, I2C, UART), and the target MCUs have hardware peripherals for I2C/UART that make most of this firmware trivial rather than a port.

Decision: the RTL stands alone as a Tiny Tapeout / portfolio piece (to be validated on an iCE40 breakout board separately, not integrated into the controller). The shipped controller is MCU-only.

**2. MCU: nRF52840** (Raytac MDBT50Q-P1MV2 module), chosen over ESP32 (much higher active/BLE current, 70–380mA range) and RP2040 (no native BLE radio — "RP2040W" isn't a real part; Pico W pairs RP2040 with a separate wireless chip, which is already a two-chip solution). nRF52840 draws ~4-6mA active and drops to ~1-3µA in deep sleep with GPIO-driven wake, which matters a lot given a gamepad sits idle most of its powered-on time.

**3. Top/bottom interconnect: I2C, not parallel GPIO.**
The original RTL reads 12+ individual button lines as raw parallel GPIO. Routing that many individual contacts across a slide/hinge joint is a mechanical reliability and connector-size problem. Instead: a 16-bit I2C GPIO expander (MCP23017) lives in the bottom module and reads all discrete buttons locally, putting them on the same I2C bus as the trackpads. This collapses the top/bottom connector down to ~4-5 contacts: VCC, GND, SDA, SCL, optional INT (wake-on-press).

**4. Trackpads: Cirque Pinnacle-based GlidePoint Circle Trackpads** (35mm, I2C variant), one per side, for capacitive touch (Steam Controller-style). Notable: the existing RTL's `i2c_master` instances already use device addresses `0x2A` and `0x2C` — which are exactly the Cirque Pinnacle default and resistor-mod-alternate I2C addresses. The RTL was apparently already designed around this part. L3/R3 (trackpad click) uses the Pinnacle ASIC's own onboard button GPIO pins, reported in the same I2C stream as touch data — not wired through the GPIO expander. Full pin behavior still needs confirming against the complete Pinnacle datasheet before schematic finalization.

**5. Triggers: binary, not analog.**
Considered analog (variable-pressure) triggers but decided against — added ADC chip, calibration, and noise-sensitive analog signals crossing the slide/hinge connector, for a feature most games treat as a threshold press anyway. Triggers are two more digital lines into the GPIO expander (14 total discrete buttons: ABXY ×4, D-pad ×4, bumpers ×2, triggers ×2, start, select).

**6. No battery — wired-only, powered directly from USB-C.** Originally spec'd a 5000mAh Li-ion cell with an MCP73831 charger. Dropped after the battery connector (J4, JST PH series) turned into a multi-hour sourcing/schematic-symbol dead end, and a step back showed the simpler fix: don't carry a battery at all. VBUS from J1 now feeds VCC directly — no charger IC, no PROG resistor, no charge-status handling, no J4.

**Consequence, stated plainly:** this removes untethered BLE play, which was objective #1 from the start ("a Bluetooth controller for my own enjoyment"). The board only works while plugged in via USB-C. BLE hardware/firmware can still exist and be exercised for testing, but there's no real wireless-gameplay use case without a power source when unplugged. This was a deliberate trade — simplicity and a shippable prototype over the original wireless pitch — not an oversight. Revisit if that trade turns out to be the wrong one once there's a working unit in hand.

---

## Bill of materials

See `mag_deck_v2_BOM.xlsx` — full parts list with quantities, unit pricing, and sourcing notes. Current single-prototype-unit estimate: **~$85** (hobbyist/low-qty pricing; drops significantly at volume). Dropped ~$16 by removing the battery/charger cluster (see decision #6).

Open items in the BOM: top/bottom module connector part number (pending mechanical spec), both PCB fab line items (placeholder cost pending actual board size/layer count), and whether to keep the power switch now that it's no longer gating a battery (see decision #6 and `wiring_chart.md` section 5).

---

## Next steps

- [ ] **PCB design tool: Altium.** Starting schematic capture for both boards.
- [ ] Top module schematic: nRF52840 module, USB-C power (no battery/charger — see decision #6), MagSafe ring integration, BLE antenna keepout.
- [ ] Bottom module schematic: GPIO expander wiring for 14 buttons, 2x Cirque trackpad I2C connections, connector footprint.
- [ ] Confirm Cirque Pinnacle button-pin behavior against full datasheet (L3/R3 confirmation).
- [ ] Finalize top/bottom connector part (pogo pins vs castellated contacts vs magnetic pogo pad) — gates both PCB connector footprint and hinge/slide CAD.
- [ ] 3D fit-check: export populated board STEP models from Altium, import into `CAD/controller.FCStd` assembly alongside `frontPlate`/`backPlate`/`shell` to verify real component clearance (battery volume, connector, hinge range of motion) before committing to full routing.
- [ ] PCB layout/routing once fit is confirmed.
- [ ] Fab (JLCPCB/PCBWay-class), then assembly (all parts in the BOM are hand-solderable; no BGA/fine-pitch parts — SMT assembly service is a legitimate option if time-constrained).
- [ ] Firmware: port debounce/poll/packet logic from RTL to nRF52840 firmware — I2C reads of expander + trackpads, BLE HID report assembly (not the RTL's UART packet format, which is for RTL bench validation only), sleep/wake on INT line.
- [ ] Separately: get the standalone RTL running on an iCE40 breakout board for the Tiny Tapeout / portfolio track — independent of the shipped controller.

---

## Hardware RTL (portfolio / Tiny Tapeout track — not shipped)

`Hardware Verilog/unit/` — hand-written SystemVerilog, not AI-generated, kept that way intentionally:
- `debounce.sv` — double-flop sync + threshold debounce
- `i2c_master.sv` — bit-banged I2C master FSM (targets Cirque Pinnacle addressing, 0x2A/0x2C)
- `input_mapper.sv` — combinational packet assembly
- `tx_encoder.sv` / `uart_tx.sv` — UART packet serialization
- `analog_sampler.sv` — stub, not yet implemented (was for analog triggers; triggers are now binary, so this may end up out of scope for the product but could still be relevant for RTL portfolio purposes)

Testbenches in `Hardware Verilog/testBenches/`.

---

## License

MIT License — see `LICENSE`.
