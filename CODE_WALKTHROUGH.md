# Logic Analyzer Verilog Walkthrough

Reference guide matching [logic_analyzer.v](logic_analyzer.v) (updated as we add VGA, UI controls, and PCB integration).

---

## 1. Signal Flow Overview
1. **`probes_in[7:0]`** (from `test_gen` or `GPIO_0`) enters **`sync_2ff`**, which outputs **`synced_sample[7:0]`**.
2. **`synced_sample`** is the *only* version of the pins that the rest of the FPGA sees—it feeds both **`trigger_unit`** and **`ram_8kx8` (`wr_data`)**.
3. **`rate_divider`** generates a 1-clock **`sample_en`** pulse at the chosen sample rate (`50 MSPS` down to `10 kSPS`). Everything stays clocked on `CLOCK_50`.
4. **`trigger_unit`** watches **`synced_sample`** and pulses **`trig_fire = 1`** when the trigger condition hits.
5. **`capture_fsm`** controls **`wr_en`** and **`wr_addr`** to fill all 8192 slots of **`ram_8kx8`** (`mem[0..8191]`).

---

## 2. `top` (Lines 1–77)
* Wires `test_gen` and `logic_analyzer_core` together internally (`SW[9] = 1` feeds `test_out`, `SW[9] = 0` reads `GPIO_0[7:0]`).
* **`SW[8]`** picks `50 MSPS` (`0`) vs `10 MSPS` (`1`).
* **`SW[7]`** switches between **Snapshot mode (`0`)** using `KEY[1]`, and **Live Continuous mode (`1`)** auto-rearming via `live_timer` (~60 Hz).
* **`KEY[0]`** = Reset, **`KEY[1]`** = Arm capture (in Snapshot mode).
* **`SW[6:0]` → `LEDR[7:0]`:** Lets you step through captured RAM slots `0..127` on the LEDs (`LEDR[8]` = `busy`, `LEDR[9]` = `done`) before VGA is added.

---

## 3. `sync_2ff` (Lines 184–201)
* **Internal registers:** `stage1` (Flop 1), `sync_out` (Flop 2).
* **How it works:** On every `posedge clk`, `stage1 <= async_in` and `sync_out <= stage1`.
* **Why `sync_out` = what the program sees:** `stage1` absorbs any setup/hold violation on raw `probes_in` and gets a full 20 ns cycle to settle; `sync_out` (`synced_sample` in `logic_analyzer_core`) is guaranteed clean for downstream logic.

---

## 4. `trigger_unit` (Lines 204–232)
* **Internal register:** `prev_sample[7:0]` — updates *only* when `sample_en == 1`, so it always holds **one sample ago** at the selected sample rate.
* **Channel pickers:**
  * `curr_bit = sample[trig_ch]`
  * `prev_bit = prev_sample[trig_ch]`
* **Combinational `case (trig_mode)` → `trig_fire`:**
  * `2'b00` (**Rising edge**): `curr_bit & ~prev_bit` (`1` now, `0` last sample)
  * `2'b01` (**Falling edge**): `~curr_bit & prev_bit` (`0` now, `1` last sample)
  * `2'b10` (**Either edge**): `curr_bit ^ prev_bit` (changed since last sample)
  * `2'b11` (**Pattern match**): `(sample & trig_mask) == (trig_val & trig_mask)` (`1`s in `trig_mask` pick which channels matter; `0`s are ignored).

---

## 5. `capture_fsm` (Lines 235–306)
Follows the Lab 5 two-`always`-block pattern (`always @(*)` computes next state `Y_D` and `wr_en`; `always @(posedge clk)` updates `y_Q` and `wr_addr`).

* **Edge-detecting `arm`:** `arm_pulse = arm & ~arm_prev;` fires for **1 clock** when `arm` rises `0 → 1`, so holding a button doesn't re-arm repeatedly.
* **The 4 States (`y_Q`):**

| State | Code | Purpose | `wr_en` | Exit Condition |
| :--- | :---: | :--- | :---: | :--- |
| **`S_IDLE`** | `2'd0` | Resting after reset | `0` | `arm_pulse` → `S_WAIT_TRIG` |
| **`S_WAIT_TRIG`** | `2'd1` | Watches for `trig_fire` | `1` on `sample_en && trig_fire` (saves `mem[0]`) | `sample_en && trig_fire` → `S_CAPTURE` |
| **`S_CAPTURE`** | `2'd2` | Fills `mem[1..8191]` cell by cell | `1` on `sample_en` | `wr_addr == 8191 && sample_en` → `S_DONE` |
| **`S_DONE`** | `2'd3` | Snapshot frozen (`done = 1`) for viewing | `0` | `arm_pulse` → `S_WAIT_TRIG` |

---

## 6. Supporting Modules
* **`rate_divider` (Lines 149–181):** `div_max` mux sets clocks per sample (`1` = 50 MSPS, `5` = 10 MSPS, `100` = 500 kSPS, etc.). `sample_en` pulses high for 1 clock whenever `cnt >= div_max - 1`.
* **`ram_8kx8` (Lines 309–323):** `mem[0:8191]` array; writes `wr_data` when `wr_en == 1`, outputs `rd_data` **1 clock after** `rd_addr` updates.
* **`test_gen` (Lines 326–359):** Generates a `10 MHz` wave (`ch0`), `5 MHz` (`ch1`), 4-bit counter (`ch5:2`), 1-clock periodic pulse (`ch6`), and ~`781 kHz` wave (`ch7`).
* **`live_timer` (Lines 362–392):** Fires `refresh_pulse` immediately when `SW[7]` turns ON, then every `833,333` clocks (~`60 Hz`) for tear-free continuous refreshing.

---

## Upcoming Sections *(To Add Next)*
* [ ] **`vga_drawer`:** Sweeping `x = 0..319`, reading `ram_8kx8`, plotting 8 digital lanes + grid + cursors.
* [ ] **Milestone 2 Upgrades:** Pre/post-trigger circular buffer (`pre_samples`) + debounced UI + `HEX0–5`.
