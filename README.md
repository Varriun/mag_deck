# mag_deck

A split gaming controller for foldable phones — a top module with a MagSafe-style ring and BLE MCU, and a bottom module with buttons, digital triggers, and two capacitive trackpads (Steam Controller-inspired).

The repository has two independent tracks:

| Track | What it is | Status |
|---|---|---|
| **[RTL](#rtl-systemverilog)** | SystemVerilog implementation of the controller's input pipeline: debounce → packetize → UART, plus I2C trackpad polling. Portfolio / Tiny Tapeout track. | Simulation-verified (5 self-checking testbenches). Not yet synthesized or run on hardware. |
| **[Product hardware](#product-hardware-v2)** | The physical controller: nRF52840 MCU, I2C GPIO expander, Cirque trackpads, Altium schematic, FreeCAD enclosure. | Architecture and parts selected; schematic capture in progress. |

The shipped controller does **not** use the RTL — see [design decision 1](#key-design-decisions).

---

## RTL (SystemVerilog)

### Block diagram

```
                  ┌──────────────────────────── mag_deck_core ────────────────────────────┐
 14 buttons ──────┼─► debounce ×14 ─► register ─┐                                          │
 (ABXY, D-pad,    │   (2-flop sync +            │                                          │
  L1/R1, L2/R2,   │    1 ms filter)             ▼                                          │
  start, select)  │                       input_mapper ──► tx_encoder ──► uart_tx ─────────┼──► tx_pin
                  │                        (5-byte pkt)     (latch pkt,    (8N1,           │    115200 baud
                  │   poll timer ──poll_tick──┬─► pkt_valid   send bytes)    115200)        │
                  │   (100 Hz)                │                     ▲                       │
                  │                           ├─► i2c_master (0x2A) ┤ tp_data_1 ◄──────────┼──► SCL1 / SDA1
                  │                           └─► i2c_master (0x2C) ┘ tp_data_2 ◄──────────┼──► SCL2 / SDA2
                  └────────────────────────────────────────────────────────────────────────┘
```

### Modules (`unit/`)

| Module | Function |
|---|---|
| `mag_deck_core.sv` | Top level. Instantiates and wires everything below; generates the 100 Hz `poll_tick`; holds the latest trackpad bytes. |
| `debounce.sv` | Two-flop synchronizer (metastability) followed by a counter that only accepts a new level after it has been stable for `THRESHOLD` cycles. |
| `i2c_master.sv` | FSM-based I2C master (100 kHz, open-drain SDA). Performs a register read: START → address+W → register → repeated START → address+R → 1 data byte → NACK → STOP. |
| `input_mapper.sv` | Combinational packet assembly; `pkt_valid` is the poll strobe. |
| `tx_encoder.sv` | Latches the packet on `pkt_valid`, then hands bytes to the UART one at a time using a `tx_start` / `tx_busy` handshake. |
| `uart_tx.sv` | UART transmitter, 8N1, LSB first. |

### Packet format

Sent every 10 ms (100 Hz), 5 bytes, over UART at 115200 baud (~434 µs per packet):

| Byte | Bit 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|---|---|
| `pkt[0]` | sync = `0xAA` |||||||
| `pkt[1]` | 0 (spare) | 0 (spare) | L2 | R2 | start | select | L1 | R1 |
| `pkt[2]` | A | B | X | Y | up | down | left | right |
| `pkt[3]` | left trackpad data byte |||||||
| `pkt[4]` | right trackpad data byte |||||||

The two spare bits are reserved for L3/R3 or a trackpad-error flag.

### Key parameters

| Parameter | Value |
|---|---|
| System clock | 50 MHz (currently fixed — see [limitations](#known-limitations)) |
| Debounce | 50,000 cycles = 1 ms |
| Poll / packet rate | 100 Hz (`poll_tick` every 500,000 cycles) |
| UART | 115200 baud, 8N1 (divisor 434) |
| I2C | 100 kHz, trackpad addresses `0x2A` / `0x2C` (Cirque Pinnacle default / alternate) |

### Design notes

- **Buttons are synchronized before anything else.** Every button input passes through two flip-flops before the debounce logic, so an asynchronous edge can't cause metastability downstream.
- **Each packet is consistent.** `tx_encoder` copies all 5 bytes when `pkt_valid` fires and sends from that copy. A packet can never mix old and new data, even though transmission takes ~434 µs.
- **Trackpad data is one poll period old.** The same `poll_tick` both sends the packet and starts the I2C reads, which finish ~380 µs later. Packet *N* therefore carries the trackpad data from poll *N−1* (10 ms latency) — acceptable for a controller, and it keeps the timing simple.
- **Digital triggers, not analog.** Two bits in an existing byte instead of an ADC interface and two more packet bytes.

### Verification

Five self-checking testbenches in `testBenches/`, 47 checks total:

| Testbench | Level | Checks | What it verifies |
|---|---|---|---|
| `input_mapper_tb` | unit | 13 | Packet layout for all-zero and known input patterns; each trigger bit position; `pkt_valid` strobe |
| `tx_encoder_tb` | unit | 6 | Byte order across a full packet with a modeled UART busy handshake; return to idle |
| `uart_tx_tb` | unit | 12 | Start bit, 8 data bits (LSB first), stop bit sampled mid-bit; `tx_busy` and idle level |
| `i2c_master_tb` | unit | 3 | Full register-read transaction against an I2C target model (with bus pull-up): received byte, one-cycle `rx_valid`, bus released after STOP |
| `core_boot_tb` | integration | 13 | Whole pipeline from button pins to UART output: bounce filtering, every byte of a decoded packet, I2C clock activity on both buses, return to idle, second packet on schedule |

Every testbench uses a shared scoreboard (`testBenches/tb_checks.svh`):

- each check is counted and printed as PASS/FAIL;
- comparisons use `===`, so an X or Z value can never pass;
- a final summary line, and **a non-zero exit code on any failure**, so it can run unattended;
- a watchdog that fails the test if the simulation hangs waiting for an event.

**Run all tests** (requires [Icarus Verilog](https://steveicarus.github.io/iverilog/) 12+):

```bash
./run_tests.sh              # all five
./run_tests.sh uart_tx      # a single testbench
```

```
── core_boot_tb
  CHECKS: 13   PASS: 13   FAIL: 0
  TEST PASSED

ALL 5 TESTBENCHES PASSED
```

Waveforms (`*.vcd`) are written to the repo root and can be opened with GTKWave.

### Lint

`.svlint.toml` configures [svlint](https://github.com/dalance/svlint) (used by the `svls` language server) with the `designintent` rule set, minus a few style-only rules. The RTL has also been reviewed with `verilator --lint-only -Wall` (remaining warnings are width-extension notes on constants).

### Known limitations

- **Not synthesized yet.** Next step: Yosys + nextpnr for iCE40 to confirm it synthesizes and to get resource and timing figures.
- **Clock frequency is hard-coded** to 50 MHz in several modules; iCE40 boards typically run at 12 MHz. Needs a shared parameter.
- **No FPGA top level.** `mag_deck_core` is the top; a board wrapper (reset synchronizer, `SB_IO` open-drain pads, pin mapping) is still to be written, along with its testbench.
- **I2C NACKs are ignored.** A missing trackpad reads back as `0xFF` and is reported as data.
- **One byte per trackpad.** Real Pinnacle position data spans several registers; the RTL reads a single register per poll.

### Authorship

The RTL in `unit/` was written by hand. The verification infrastructure — the shared scoreboard, the testbench conversions to it, `run_tests.sh` — and the lint configuration were developed with AI assistance (Claude).

---

## Product hardware (v2)

### Key design decisions

1. **No FPGA in the shipped product.** Debounce, I2C, and UART are standard MCU-peripheral work; nothing in the controller needs dedicated logic. The RTL stays a separate portfolio / Tiny Tapeout track.
2. **MCU: nRF52840** (Raytac MDBT50Q-P1MV2 module) — native BLE, ~4–6 mA active and ~1–3 µA in deep sleep with GPIO wake. Chosen over ESP32 (much higher current) and RP2040 (no on-chip radio).
3. **Buttons go through an I2C GPIO expander** (MCP23017) in the bottom module, sharing the I2C bus with the trackpads. This cuts the top/bottom connector down to ~4–5 contacts (VCC, GND, SDA, SCL, optional INT) instead of one wire per button. (The RTL track still reads buttons as parallel inputs.)
4. **Trackpads: Cirque GlidePoint Circle (Pinnacle ASIC), 35 mm, I2C**, one per side, at addresses `0x2A` / `0x2C`. L3/R3 use the Pinnacle's own button inputs. *(Pin behavior still to be confirmed against the full datasheet.)*
5. **Digital triggers.** Analog triggers would need an ADC, calibration, and noise-sensitive analog signals across the hinge connector, for a feature most games treat as a threshold press. 14 digital buttons total: ABXY, D-pad, L1/R1, L2/R2, start, select.
6. **No battery — USB-C powered only.** Removing the charger and battery simplified the design considerably, at the cost of untethered wireless play. A deliberate trade; to be revisited once a working unit exists.

### Status

- Altium schematic capture in progress — net-by-net progress in [`PCB_Project/wiring_chart.md`](PCB_Project/wiring_chart.md).
- Bill of materials: [`mag_deck_v2_BOM.xlsx`](mag_deck_v2_BOM.xlsx) — about **$85** for one prototype at hobbyist pricing. Open items: top/bottom connector part, PCB fab cost, whether to keep the power switch.
- Enclosure and mechanism: FreeCAD models in [`CAD/`](CAD/), mount mechanism notes in [`mount_mechanism_sketch.md`](mount_mechanism_sketch.md).

### Next steps

- [ ] Finish schematics: top module (nRF52840, USB-C power, MagSafe ring, antenna keep-out) and bottom module (expander for 14 buttons, 2× trackpad connectors).
- [ ] Confirm Pinnacle button-pin behavior (L3/R3) against the full datasheet.
- [ ] Choose the top/bottom connector (pogo pins, castellated contacts, or magnetic pogo pad).
- [ ] 3D fit check: import the populated board models into the FreeCAD assembly before routing.
- [ ] PCB layout, fabrication, assembly (all parts are hand-solderable).
- [ ] Firmware for the nRF52840: I2C reads of the expander and trackpads, BLE HID reports, sleep/wake on the INT line.

---

## Repository layout

```
unit/                 RTL (SystemVerilog)
testBenches/          testbenches + shared scoreboard (tb_checks.svh)
run_tests.sh          run every testbench
.svlint.toml          lint rules
PCB_Project/          Altium schematic project + wiring chart
CAD/                  FreeCAD enclosure and mechanism models
CAD_outshell/         reference photos
mag_deck_v2_BOM.xlsx  bill of materials
```
