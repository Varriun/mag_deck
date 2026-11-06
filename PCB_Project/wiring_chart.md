# mag_deck v2 — Wiring / Net Chart

Reference for wiring the schematic. Format: `Designator.Pin -> Net / Destination`. Nets in **bold** are shared buses touched by multiple parts — wire every occurrence of that net name together.

Items marked **TODO** are open decisions or missing parts, not yet resolved — don't wire those nets until confirmed.

---

## Architecture change (this update): battery dropped, wired-only USB-C power

**Decision:** no onboard battery. U1 (MCP73831 charger), C1, R1 (PROG resistor), and J4 (battery connector) are all removed from the design. The board runs entirely on VBUS from the USB-C connector (J1) — powered only while plugged in.

**What this simplifies:** the entire charger cluster is gone. No more VBAT net, no STAT pin decision, no PROG resistor sizing, no J4 connector sourcing headache (this is what killed the last hour — J4 was never going to be a simple part, see prior PHR-2 saga). VCC is now just VBUS, directly.

**What this costs:** the controller only works while tethered via USB-C. No untethered BLE gameplay — which was objective #1 from day one ("a Bluetooth controller for my own enjoyment"). BLE radio can still exist in firmware/hardware and pair for testing, but there's no practical wireless-play use case without a power source when unplugged. Flagging this plainly since it's a scope change, not just a component removal — revisit if this wasn't the intent.

---

## Wiring progress tracker

Physical wiring status in Altium, updated as you go — separate from the decisions/TODOs below.

- **GND** — mostly done: J1A (MNT1-4), J1B (A1, A12), J1C (B1, B12), U2.VSS, R3.pin2, MD1's GND pins all connected. **Still need:** C2.pin2, J2A.pin2, J3A.pin2, all SW1-14 B-side pins, J5A's GND pins, SW15 if kept.
- **VBUS / VCC** — now the same net (no separate charger stage). Connector side done: J1B (A4, A9), J1C (B4, B9). **Still need:** tie straight through to U2.VDD (done), MD1.VCC/VCCH, R2.pin2, R5.pin2, J2A.pin1, J3A.pin1, U2.RESET, C2.pin1. Recommend just labeling all of these **VCC** directly — no separate VBUS net needed anymore unless you want to keep the name for clarity at the connector end.
- **SDA / SCL** — not started.
- **Buttons (SW1-14 -> GPA0-7/GPB0-7)** — not started.
- **D1 -> MD1.USB-D+/USB-D-** — not started (D1's input side from J1 is done; output side to MD1 still needs the long run, and pinout still needs datasheet verification per section 6).
- **SWD header (J5A), power switch (SW15 — now optional, see note in section 5)** — not started.

**Removed from this chart (no longer applicable):** U1 (MCP73831 charger), C1 (charger decoupling), R1 (PROG resistor), J4 (battery connector), VBAT net.

---

## 1. Power nets (summary)

| Net | What it is |
|---|---|
| **VBUS / VCC** | 5V from USB-C, feeds the board directly — no charger, no regulator, no battery in between. BMD-340 datasheet confirms 1.7V-5.5V operating supply with built-in DC/DC, so this is safe to tie straight through. **Remaining nuance:** confirm in BMD-340's full datasheet pinout section whether VCC and VCCH tie together or need separate treatment before finalizing that specific pair. |
| **GND** | Common ground — everything with a GND/VSS pin joins this net |

---

## 2. USB-C connector (J1A / J1B / J1C, part 2295018-2)

| Pin | Net |
|---|---|
| J1A.MNT1-4 | **GND** (shield/mechanical ground) |
| J1B.GND (A1) | **GND** |
| J1B.TX1+ (A2) | No Connect |
| J1B.TX1- (A3) | No Connect |
| J1B.VBUS (A4) | **VCC** |
| J1B.CC1 (A5) | R3.pin1 (5.1k pulldown) |
| J1B.D+ (A6) | **USB_D+_RAW** -> into D1 (NUP2105LT1G) — see section 6 |
| J1B.D- (A7) | **USB_D-_RAW** -> into D1 — see section 6 |
| J1B.SBU1 (A8) | No Connect |
| J1B.VBUS (A9) | **VCC** |
| J1B.RX2- (A10) | No Connect |
| J1B.RX2+ (A11) | No Connect |
| J1B.GND (A12) | **GND** |
| J1C.GND (B1) | **GND** |
| J1C.TX2+ (B2) | No Connect |
| J1C.TX2- (B3) | No Connect |
| J1C.VBUS (B4) | **VCC** |
| J1C.CC2 (B5) | R4.pin1 (5.1k pulldown) |
| J1C.D+ (B6) | **USB_D+_RAW** (same net as A6 — tied together per USB-C spec for cable-flip tolerance, both feed into D1) |
| J1C.D- (B7) | **USB_D-_RAW** (same net as A7) |
| J1C.SBU2 (B8) | No Connect |
| J1C.VBUS (B9) | **VCC** |
| J1C.RX1- (B10) | No Connect |
| J1C.RX1+ (B11) | No Connect |
| J1C.GND (B12) | **GND** |

R3.pin2 -> **GND**. R4.pin2 -> **GND**. (Both pull-downs complete the CC-line power-sink signaling.)

**Note:** pins previously labeled VBUS here now simply merge into the VCC net directly (no charger stage between them anymore) — relabel as VCC on the schematic if you haven't already, or keep VBUS as the label at just this connector for clarity and let Altium's by-name merge handle it. Either works electrically; pick one and be consistent.

---

## 3. I2C bus (U2 = MCP23017, J2/J3 = trackpads, MD1 = BMD-340-A-R)

| Pin | Net |
|---|---|
| U2.VDD (9) | **VCC** |
| U2.VSS (10) | **GND** |
| U2.A0 (15) | **GND** (address bit 0) |
| U2.A1 (16) | **GND** (address bit 1) |
| U2.A2 (17) | **GND** (address bit 2) — all three low sets I2C address 0x20, no conflict with trackpad (0x2A/0x2C) |
| U2.SCK (12) | **SCL** |
| U2.SDA (13) | **SDA** |
| U2.RESET (18) | **VCC** (tie high — out of reset) |
| U2.INTA (20) | MD1 GPIO — **TODO: pick a P0.xx pin** (e.g. P0.28) if you want wake-on-button-press. Skip if not using the low-power wake feature. |
| U2.INTB (19) | No Connect (or mirror to INTA via IOCON if you want both ports' interrupts on one line — optional, decide with INTA) |
| C2.pin1 | **VCC** (decoupling, at U2.VDD) |
| C2.pin2 | **GND** |
| R2.pin1 | **SDA** |
| R2.pin2 | **VCC** |
| R5.pin1 | **SCL** |
| R5.pin2 | **VCC** |
| J2A.pin1 | **VCC** |
| J2A.pin2 | **GND** |
| J2B.pin3 | **SDA** |
| J2B.pin4 | **SCL** |
| J3A.pin1 | **VCC** |
| J3A.pin2 | **GND** |
| J3B.pin3 | **SDA** |
| J3B.pin4 | **SCL** |
| MD1 — SDA pin | **P0.26** (locked in — assign in firmware to match) |
| MD1 — SCL pin | **P0.27** (locked in — assign in firmware to match) |
| MD1.VCC (17, 65) | **VCC** |
| MD1.VCCH (66) | **VCC** (or check datasheet — may be a separate high-voltage rail, confirm before tying to same net) |
| MD1.VBUS | **VCC** (same net now — USB detection feature, if used, is moot since VCC only exists when USB is plugged in anyway) |
| MD1 GND pins (all) | **GND** |
| MD1.USB-D+ | **USB_D+** (clean side of D1, post-protection) |
| MD1.USB-D- | **USB_D-** (clean side of D1) |

---

## 4. Buttons (SW1-14 -> U2 GPA0-7 / GPB0-7)

**TODO: confirm this mapping matches your intended button layout** (from the earlier ASCII sketch — ABXY, D-pad, bumpers, triggers, start/select). Proposed assignment below, change freely:

| Switch | Function | U2 Pin |
|---|---|---|
| SW1 | A | GPA0 |
| SW2 | B | GPA1 |
| SW3 | X | GPA2 |
| SW4 | Y | GPA3 |
| SW5 | D-pad Up | GPA4 |
| SW6 | D-pad Down | GPA5 |
| SW7 | D-pad Left | GPA6 |
| SW8 | D-pad Right | GPA7 |
| SW9 | L1 (bumper) | GPB0 |
| SW10 | R1 (bumper) | GPB1 |
| SW11 | L2 (trigger) | GPB2 |
| SW12 | R2 (trigger) | GPB3 |
| SW13 | Start | GPB4 |
| SW14 | Select | GPB5 |
| — | (spare, L3/R3 headroom — both trackpads report click via I2C, no separate wiring needed) | GPB6, GPB7 unused |

Each switch: pin A1 (or A2, tied together) -> its GPA/GPB pin above. Pin B1 (or B2, tied together) -> **GND**. (Buttons are simple pull-to-ground switches; MCP23017's internal pull-ups handle the rest — confirm you're enabling internal pull-ups in firmware, or add external pull-ups if not.)

---

## 5. SWD programming header (J5A, part SHF-105-01-L-D-TH) and power switch (SW15)

**TODO: confirm exact pinout against the SWD/Cortex Debug standard** (this is a proposed standard 10-pin assignment, verify against your programmer/probe):

| Pin | Net |
|---|---|
| J5A.1 | **VCC** |
| J5A.3 | MD1.SWDIO |
| J5A.5 | **GND** |
| J5A.7 | MD1.SWCLK |
| J5A.9 | **GND** (or RESET, if MD1 exposes a reset pin — check datasheet) |
| (even pins, B-side) | Typically GND/key — check your specific probe's pinout before finalizing |

**SW15 (power switch) — TODO, open decision:** it used to gate VBAT->VCC while leaving charging active regardless of switch position. That whole rationale is gone now — there's no battery to leave charging. Options:
1. **Drop it entirely.** Board is on whenever USB is plugged in, off when unplugged. Simplest, one less part, one less BOM line.
2. **Keep it as a simple VCC in-line switch** (J1.VBUS -> SW15 -> everything else), purely so you can power the board off without physically unplugging USB. Minor convenience, ~$0.60 BOM cost, still needs pins wired.

Not resolved — pick one before wiring this net.

---

## 6. USB data lines (optional wired USB HID, alongside BLE)

Decided: BMD-340's onboard USB peripheral gets wired up now (cheap, ~1 part) so the board has the *option* of wired USB HID, without committing to writing that firmware now. Given the battery is gone, wired USB HID is arguably now the *primary* mode, not a fallback — worth reconsidering firmware priority later.

**RESOLVED (part):** D1 = NUP2105LT1G, placed. **TODO (pinout):** the placed symbol only shows 3 pins (1, 2, 3) — verify against the actual NUP2105LT1G datasheet which physical pin is which before wiring, don't assume. Proposed mapping below, confirm before committing:

| Pin | Net |
|---|---|
| D1.pin1 | **USB_D+_RAW** (from J1B.A6 / J1C.B6) — **verify against datasheet** |
| D1.pin2 | **USB_D-_RAW** (from J1B.A7 / J1C.B7) — **verify against datasheet** |
| D1.pin3 | **GND** — **verify this is actually the common/ground pin and not a third signal line** |
| MD1.USB-D+ | **USB_D+** (clean side — if D1 is genuinely 3-pin with a shared common line, the "clean" output may share the same physical node as the input on this style of part; confirm from datasheet whether D1 clamps in-line or needs separate in/out nodes) |
| MD1.USB-D- | **USB_D-** |

---

## Open TODOs before wiring is complete

**Resolved this session:**
- ~~Place second 4.7k resistor (R5) for the SCL pull-up.~~ Done.
- ~~Confirm MD1 accepts VBAT directly or needs a regulator.~~ No regulator needed.
- ~~Pick specific P0.xx pins on MD1 for SDA, SCL.~~ P0.26 = SDA, P0.27 = SCL.
- ~~Place USB D+/D- ESD protection part.~~ D1 (NUP2105LT1G) placed.
- ~~Decide exactly where SW15 sits in the power path.~~ Superseded — battery dropped, see section 5 for the new (unresolved) question.
- ~~Battery connector (J4) sourcing.~~ Moot — battery dropped entirely.

**Still open:**
1. **Verify D1's actual pinout against the NUP2105LT1G datasheet** before wiring it — only 3 pins are visible on the placed symbol, don't assume pin1=D+/pin2=D-/pin3=GND without checking.
2. Confirm exactly how VCCH relates to VCC on MD1 (tie together or separate) via BMD-340's full datasheet pinout section.
3. Decide INTA/INTB usage (wake-on-press feature or skip) — if yes, still need a P0.xx pin for it.
4. Confirm button-to-GPA/GPB mapping matches your intended layout.
5. Confirm SWD header pinout against your actual debug probe.
6. **Decide SW15's fate** — keep as a simple on/off, or drop it (section 5).
