# DE1-SoC Demo Cheat Sheet

Quick hardware and demo reference for [logic_analyzer.v](logic_analyzer.v) (`top` module).

---

## Pre-Demo Checklist (Before Connecting Board)

1. **Import DE1-SoC Pin Assignments:** Open `logic-analyzer.qpf` in Quartus → **`Assignments` → `Import Assignments...`** → select `DE1_SoC.qsf` (required so `CLOCK_50`, `SW`, `KEY`, `LEDR`, `GPIO_0`, and `GPIO_1` map to real board pins).
2. **Compile Bitstream:** Press **`Ctrl + K`** (Full Compilation).
3. **Program FPGA:** **`Tools` → `Programmer`** → **`Start`** to load the `.sof` onto the DE1-SoC.
4. **ModelSim Check (if asked):** Run `do sim/run_sim.do` and confirm Transcript prints `ALL TESTS PASSED!`.

---

## Pins, Switches & LEDs

### Inputs
| Control | Function | Settings |
| :--- | :--- | :--- |
| **`KEY[0]`** | Reset (active-low) | Press = reset FSM and counters to `IDLE`; release = run |
| **`KEY[1]`** | Arm / Capture | Press once in Snapshot mode (`SW[7] = 0`) to trigger a capture |
| **`SW[9]`** | Probe source | `1` = internal `test_gen` loopback (no wires), `0` = external `GPIO_0[7:0]` |
| **`SW[8]`** | Sample rate | `0` = `50 MSPS` (every clock), `1` = `10 MSPS` (every 5th clock) |
| **`SW[7]`** | Capture mode | `0` = Snapshot (`KEY[1]`), `1` = Live continuous (~`60 Hz` auto-rearm) |
| **`SW[6:0]`** | RAM slot address | Binary `0`–`127` to read back captured samples on `LEDR[7:0]` |
| **`GPIO_0[7:0]`** | External probes | 8 digital input channels `ch0..ch7` (**3.3 V max**, used when `SW[9] = 0`) |

### Outputs
| Pin / LED | Function | Meaning |
| :--- | :--- | :--- |
| **`LEDR[7:0]`** | Captured sample | Displays `ch7..ch0` stored at RAM slot `SW[6:0]` (`mem[SW[6:0]]`) |
| **`LEDR[8]`** | `busy` | `1` while waiting for rising edge on `ch0` or filling RAM |
| **`LEDR[9]`** | `done` | `1` once all 8,192 samples are captured and frozen |
| **`GPIO_1[7:0]`** | `test_gen` out | Always outputs: `ch0` = 10 MHz, `ch1` = 5 MHz, `ch5:2` = 4-bit counter, `ch6` = pulse, `ch7` = ~781 kHz |

---

## 3-Step Live Demo Flow

1. **Snapshot Mode (No Wires):**
   - Set `SW[9] = 1` (internal test gen), `SW[8] = 0` (`50 MSPS`), `SW[7] = 0` (Snapshot), `SW[6:0] = 0000000`.
   - Press `KEY[0]` (reset), then press **`KEY[1]`** → **`LEDR[9]` (`done`) turns ON**.
   - Step **`SW[6:0]`** through `0, 1, 2, 3, 4`: `LEDR[0]` (`ch0`, 10 MHz wave triggered on rising edge) follows `1 → 1 → 0 → 0 → 0`, and `LEDR[7:1]` show the other captured channels.
2. **Live Continuous Mode (`60 Hz`):**
   - Keep `SW[8] = 0` (`50 MSPS`) and flip **`SW[7] = 1`** → `live_timer` automatically re-arms capture ~60 times/sec while you inspect slots with `SW[6:0]`. *(Note: keep `SW[8] = 0` when using internal `test_gen`, because `10 MSPS` samples `ch0`'s `10 MHz` wave at the exact same point every cycle so no rising edge is seen; `SW[8] = 1` is for slower `< 5 MHz` external `GPIO_0` signals.)*
3. **External Probe Mode (Optional):**
   - Flip **`SW[9] = 0`** and jumper `GPIO_1[7:0]` (or an external `<= 3.3 V` signal) into `GPIO_0[7:0]` to show physical pin capture through `sync_2ff`.

---

## Quick TA Q&A Reminders

- **Why keep everything on `CLOCK_50` (`rate_divider` uses `sample_en`)?** Avoids derived-clock timing skew and lets RAM reads (`SW[6:0]` / future VGA) keep running smoothly at 50 MHz even during slow captures.
- **Why `sync_2ff`?** Prevents metastability on external `GPIO_0` signals so `trigger_unit` and `ram_8kx8` always see the exact same clean `synced_sample`.
- **Why an array inside `always @(posedge clk)` (`ram_8kx8`)?** Triggers Quartus **BRAM inference**, compiling `mem[0:8191]` into Cyclone V hardware M10K memory blocks instead of 65,536 logic flip-flops.
- **Why split `top` and `logic_analyzer_core`?** `logic_analyzer_core` has zero DE1-SoC pin dependencies, so the exact same module runs in ModelSim, on M1 switches/LEDs, and in M2/M3 with VGA + Khalil's ADC oscilloscope.
