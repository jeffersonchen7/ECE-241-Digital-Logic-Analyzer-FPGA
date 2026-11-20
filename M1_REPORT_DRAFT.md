# ECE241 Project — Milestone 1 Report (Draft Template)
**Team:** Jefferson Chen & Khalil Chaghouri  
**Project:** FPGA Mixed-Signal Analyzer (DE1-SoC)

---

## 1. What Each Teammate Accomplished (Milestone 1)

### Jefferson Chen (Digital Logic Analyzer)
- Designed and implemented the full 8-channel digital acquisition datapath in `logic_analyzer.v`:
  - **`sync_2ff`:** Two-stage flip-flop synchronizer on `CLOCK_50` to safely sample asynchronous `probes_in[7:0]` without metastability.
  - **`rate_divider`:** Synchronous `CLOCK_50` enable-pulse (`sample_en`) generator supporting `50 MSPS` down to `10 kSPS` without creating derived clocks.
  - **`trigger_unit`:** Edge detector (rising / falling / either on selectable `trig_ch`) and masked multi-channel pattern trigger (`(sample & trig_mask) == (trig_val & trig_mask)`).
  - **`capture_fsm`:** 4-state FSM (`S_IDLE → S_WAIT_TRIG → S_CAPTURE → S_DONE`) with edge-detected `arm` input and 13-bit `wr_addr` counter filling `8,192` samples.
  - **`ram_8kx8`:** Dual-port `8K × 8` synchronous RAM storing captured 8-channel snapshots (`mem[0..8191]`).
  - **`test_gen` & `live_timer`:** Built-in deterministic test waveform generator (`10 MHz`, `5 MHz`, 4-bit counter, pulse) and 60 Hz refresh timer for switching between Snapshot (`KEY[1]`) and Live Continuous mode (`SW[7]`).
  - **`top`:** Board-level wrapper connecting `SW[9:0]`, `KEY[3:0]`, `LEDR[9:0]`, and `GPIO` headers for hardware verification.
- Built self-checking ModelSim testbench (`sim/tb_logic_analyzer.v`) verifying `50 MSPS` edge triggering and `10 MSPS` pattern triggering.

> **[INSERT SYSTEM BLOCK DIAGRAM HERE]**

### Khalil Chaghouri (Oscilloscope / ADC Side)
> **[PASTE KHALIL'S M1 SUMMARY + BLOCK DIAGRAM HERE]**

---

## 2. Code Demoed & How It Works

### Digital Logic Analyzer (`logic_analyzer.v`)
- **Signal flow:** Raw 8-bit inputs enter `sync_2ff` (`stage1 → sync_out`) to produce `synced_sample`, which is the single clean source read by `trigger_unit` and `ram_8kx8`.
- **Sampling & Triggering:** `rate_divider` emits a 1-clock `sample_en` strobe at the selected rate (`50 MSPS` when `rate_sel = 0`). `trigger_unit` registers `prev_sample` on each `sample_en` tick and asserts `trig_fire = 1` when the selected edge or masked bit pattern matches.
- **Capture & Readout:** On a rising `arm` edge (`arm_pulse`), `capture_fsm` resets `wr_addr` to `0` and enters `S_WAIT_TRIG`. On the first `trig_fire` tick, it writes the trigger sample into `mem[0]` and advances to `S_CAPTURE`, filling `mem[1..8191]` one byte per `sample_en` before freezing in `S_DONE` (`done = 1`).
- **Board / Simulation Controls (`top`):**
  - `SW[9]`: Selects internal `test_gen` (`1`) or external `GPIO_0[7:0]` (`0`).
  - `SW[8]`: Selects `50 MSPS` (`0`) or `10 MSPS` (`1`).
  - `SW[7]`: Switches between Snapshot mode (`0`, armed via `KEY[1]`) and 60 Hz Live mode (`1`, armed via `live_timer`).
  - `SW[6:0]`: Selects RAM read slot `0..127` displayed on `LEDR[7:0]` (`LEDR[8]=busy`, `LEDR[9]=done`).

> **[INSERT MODELSIM WAVEFORM 1: Zoomed Trigger Edge (`0–450 ns`) showing `arm`, `probes_in`, `synced_sample`, `trig_fire`, `state_dbg (0→1→2)`, and `wr_addr` incrementing `0, 1, 2...`]**  
> **[INSERT MODELSIM WAVEFORM 2: Full Run (`0–984 µs`) + Transcript showing `mem[0..9]` and `ALL TESTS PASSED!`]**

---

## 3. Work in Progress / Next Steps (With Simulations)
- **VGA Grid & 8-Channel Trace Drawer (WIP):** Next step is integrating `vga_adapter` (`320×240`) to read `ram_8kx8` via `rd_addr`/`rd_data` and plot all 8 digital traces alongside Khalil's analog trace.
- **Milestone 2 Goals:** Add circular pre/post-trigger capture (`pre_samples`), full UI controls for trigger channel/mode/pattern on the board, and hardware PCB integration.

> **[PASTE KHALIL'S CODE EXPLANATION + MODELSIM SCREENSHOTS HERE]**
