# FPGA Mixed-Signal Analyzer — Project Overview

**Board:** Terasic DE1-SoC (Cyclone V `5CSEMA5F31C6`) | **Course:** ECE241H1 F  
**Division:** **Jefferson** (8-ch Logic Analyzer, UI/VGA Frame, Cursors, Probe PCB) • **Khalil** (ADC Oscilloscope, PWM DAC, Self-Calibration)

---

## 1. What We Are Building
A two-in-one benchtop instrument implemented in Verilog on the DE1-SoC FPGA:
1. **8-Channel Digital Logic Analyzer (Yours):** Samples 8 digital pins up to **50 MSPS** (good for signals up to ~10 MHz), triggers on edges/patterns, captures pre/post-trigger history into RAM, and draws waveforms + `Δt` cursors on VGA.
2. **1-Channel Analog Oscilloscope + Self-Calibration (Khalil's):** Reads the DE1-SoC's on-board 12-bit SPI ADC, triggers on voltage level/slope, self-calibrates gain/offset using a PWM DAC, and plots the trace + calibration error on the same VGA screen.
3. **Probe PCB (Hardware Bonus):** Buffers/protects the 3.3 V FPGA pins (`74LVC245`) and conditions analog inputs. *(Always keep DE1-SoC jumper-wire testing working as a fallback.)*

---

## 2. FPGA & DE1-SoC Mental Model
Unlike a Raspberry Pi Pico (which runs C sequentially and uses PIO state machines), an FPGA builds **independent hardware circuits that all run simultaneously** on one 50 MHz clock (`CLOCK_50`, 1 tick = `20 ns`).

### DE1-SoC Hardware You Actually Touch
| Board Resource | What It Does in This Project | Important Hardware Limit |
| :--- | :--- | :--- |
| **`CLOCK_50`** | Main `50 MHz` system clock for all flip-flops & FSMs | Keep everything on this clock; use counter enable pulses (`sample_en`) for slower sample rates |
| **`GPIO_0` / `GPIO_1`** | Two 40-pin headers: `GPIO_0[7:0]` = probe inputs, `GPIO_1[7:0]` = built-in test signal outputs | **3.3 V LVCMOS max** (never feed 5 V directly without buffer/protection) |
| **`ADC 2×5 Header`** | Feeds analog signals (`0–4.096 V`) into the on-board SPI ADC (`LTC2308` @ 500 kSPS or `AD7928` @ 1 MSPS) | Much slower than 50 MSPS digital—digital and analog either run independent timebases or lock to `≤500 kSPS` together |
| **`KEY[3:0]` & `SW[9:0]`** | User controls (timebase, trigger mode, run/stop, cursor movement) | `KEY` buttons are **active-low** (`0` when pressed) and physically bounce (~10–20 ms debounce needed) |
| **`HEX0–HEX5` / `LEDR`** | Instant numeric & status readouts (timebase, cursor `Δt`, armed/triggered state) | Great for debugging before VGA is finished |
| **`VGA Port`** | 15-pin video output driven by an on-board video DAC | Standard `640×480 @ 60 Hz` monitor timing |

---

## 3. How VGA Works (Zero-Mystery Version)
A VGA monitor paints **640×480 pixels, 60 times per second**, scanning left-to-right, top-to-bottom. The FPGA drives RGB color pins plus two sync pulses (`VGA_HS` = next row, `VGA_VS` = next frame).

You have **two ways** to drive VGA in ECE241:
1. **Course `vga_adapter` (320×240, easiest to start):**  
   Starter IP that acts like a pixel canvas. Your FSM simply outputs `(x, y, colour, plot = 1)` one pixel at a time; `vga_adapter` stores the pixels in internal screen RAM and generates all monitor sync signals automatically. *(Pick `320×240`, not `160×120`—120 rows is too tight for 8 digital traces + 1 analog trace.)*
2. **Direct Scanline Renderer (640×480, cleanest long-term):**  
   A small counter sweeps `(x, y)` continuously at 25 MHz (`CLOCK_50 / 2`) and computes each pixel's color **on the fly** straight from capture RAM—zero framebuffer RAM needed, no erase/redraw flicker, and 2× sharper text/traces.

**Key rule:** Only **one** shared VGA renderer should talk to the monitor. It reads your `8K×8` RAM for the top half of the screen and Khalil’s `2K×12` RAM for the bottom half.

---

## 4. Component Breakdown

```
                 YOUR SIDE (Digital + Shell)
GPIO_1[7:0] ◄── [Test Pattern Gen]
                     │ (jumper wires or Probe PCB)
                     ▼
GPIO_0[7:0] ──► [2-FF Sync + Rate Div] ──► [Trigger (Edge/Pattern)] ──┐
                                                                      ▼
KEY / SW ────► [Debounce + UI FSM] ──────────────────────────► [Capture FSM] ──► [8K×8 Dual-Port RAM]
                                                                                         │
                 KHALIL'S SIDE (Analog + Cal)                                            ▼
ADC 2×5 ─────► [SPI ADC Ctrl] ──► [Gain/Offset Corr] ──► [Level/Slope Trig] ──► [2K×12 RAM] ──► [Shared VGA Renderer] ──► Monitor
                     ▲                    ▲                                                              │
               [PWM DAC + Cal FSM] ───────┘                                                      (Grid, 8 Dig, 1 Ana, Cursors, Cal Plot)
```

### Your Components (Jefferson)
1. **2-FF Synchronizer & Rate Divider:** Passes external `GPIO_0[7:0]` through two flip-flops on `CLOCK_50` to prevent metastability glitches, plus a counter generating a 1-clock `sample_en` pulse for slower timebases (e.g., 50M, 25M, 10M, 1M, 100k SPS).
2. **Digital Trigger Unit:** Detects rising/falling edges (`curr & ~prev`) on a selected channel, and (for Milestone 2) masked bit-pattern matches (`(sample & mask) == pattern`).
3. **Capture FSM + `8K×8` Dual-Port RAM:** Ring-buffer controller (`IDLE → PRE_FILL → WAIT_TRIG → POST_FILL → DONE`). Port A writes captured bytes; Port B lets VGA read safely without halting captures.
4. **Test Generator:** Outputs deterministic clocks/counters/bursts onto `GPIO_1` so you always have reliable signals to test and demo.
5. **UI Control FSM + Debouncer:** Cleans `KEY[3:0]` bounces and maps `SW[9:0]` + `KEY` to run/stop, timebase, trigger channel/mode, and cursor position.
6. **Shared VGA Renderer + Digital Cursors:** Draws the grid, 8 stacked channel traces (connecting `0↔1` transitions with vertical lines), trigger marker, and two movable cursors (`A`/`B`) showing `Δt` and frequency.
7. **Probe PCB (Bonus):** `74LVC245` digital buffer + diode protection + analog front-end mux/attenuator.

### Partner's Components (Khalil)
1. **Custom SPI ADC Controller:** Talks to the board's `LTC2308` or `AD7928` chip and outputs 12-bit samples.
2. **Analog Trigger + `2K×12` Dual-Port RAM:** Level/slope trigger (with small hysteresis so noise doesn't false-trigger) + circular pre/post capture.
3. **PWM DAC + Self-Calibration FSM:** Outputs test DC steps through an RC filter, reads ADC response, computes fixed-point gain/offset correction, and generates before/after error data.
4. **Analog VGA Layer + Voltage Readouts:** Renders the analog waveform, `Vpp`/min/max readouts, and the before/after calibration plot inside the shared VGA module.

---

## 5. Four Decisions to Lock In With Khalil Early
1. **VGA layout & method:** `320×240` `vga_adapter` vs `640×480` scanline, and exact `y` bounds (e.g., Digital = top half, Analog = bottom half, HUD = bottom strip).
2. **RAM read contract:** Both `8K×8` and `2K×12` RAMs expose a synchronous read port (`rd_addr` → `rd_data` 1 clock later) plus `start_ptr` (oldest sample index in the ring buffer).
3. **Mixed-signal trigger hook:** One shared `trig_fire` signal so either digital or analog can trigger both captures when locked to a common timebase.
4. **Control ownership:** Exact `SW` / `KEY` / `HEX` assignments so your digital menus and his analog/cal menus never fight over the same switches.

---

## 6. Course Deliverables & Grading Rules (ECE241H1 F)
| Deliverable | Weight | When Due | Core Requirement |
| :--- | :--- | :--- | :--- |
| **Proposal** | 1 pt | Wk 8 (Done) | Scope, block diagram, schedule |
| **Milestone 1** | 2 pts | Before **Wk 10** lab | Some RTL working on board + **ModelSim sims** + PDF report |
| **Milestone 2** | 2 pts | Before **Wk 11** lab | Most RTL on board + **ModelSim sims of internal FSMs/buffers** + PDF |
| **Presentation** | 5 pts | Before **Wk 12** lab | 10-min live demo + **detailed slides** (acts as final report) + backup video |

**Non-negotiable grading rules:**
* **FPGA-only credit:** External hardware (PCB) is a bonus; marks come strictly from Verilog running on the Cyclone V.
* **Explain your code:** TAs quiz both partners in detail on how every module works—write your own RTL and cite any course starter code (`vga_adapter`, Quartus RAM IP).
* **Equal split every week:** Both partners must demonstrate roughly equal work at M1, M2, and Final.
