# Dual‑Port RAM (Verilog‑2001) — User Guide

A practical guide to **using, simulating, and integrating** the dual‑port RAM (`ram_dp`) in your own projects.  
Works with **Icarus Verilog** (OSS CAD Suite), produces **VCD** waveforms for GTKWave, and includes a self‑checking testbench.

---

## 0) What you get
- `src/ram_dp.v` — synthesizable dual‑port RAM with **write‑first per port** + **runtime zero‑clear** (`clear_start/clear_busy/clear_done`).
- `tb/tb_ram_dp.v` — pure Verilog‑2001 **self‑checking** testbench (no SystemVerilog required).
- `docs/` — screenshots/diagrams you can view in the repo.

---

## 1) Quick start (Ubuntu / OSS CAD Suite)

```bash
# from repo root
iverilog -g2005 -o a.out src/ram_dp.v tb/tb_ram_dp.v
vvp a.out                    # runs tests; prints PASS/FAIL summary
gtkwave tb_ram_dp.vcd        # optional: open the waveform
```

**Expected console end:**
```
==== ALL TESTS PASSED ====
```

If you don’t see a VCD, ensure the TB includes:
```verilog
initial begin
  $dumpfile("tb_ram_dp.vcd");
  $dumpvars(0, tb_ram_dp);
end
```

---

## 2) Module interface (parameters & ports)

### Parameters
| Name    | Meaning                              | Typical |
|---------|--------------------------------------|---------|
| `WIDTH` | Data width per word (bits)           | 16      |
| `DEPTH` | Number of words in the RAM           | 32      |
| `ADDR_W`| Address width in bits (`ceil(log2(DEPTH))`) | 5 |

> Keep `DEPTH == 2**ADDR_W` for simple addressing. If you choose other depths, ensure `ADDR_W` is large enough to cover `DEPTH-1`.

### Ports
| Port            | Dir | Width        | Description |
|-----------------|-----|--------------|-------------|
| `clk`           | in  | 1            | Clock (posedge) for all synchronous ops |
| `rst_n`         | in  | 1            | Async‑low reset for internal clear controller regs (memory array is **not** cleared by `rst_n`) |
| **Port A**      |     |              |             |
| `a_we`          | in  | 1            | Write enable for Port A |
| `a_addr`        | in  | `ADDR_W`     | Address for Port A |
| `a_din`         | in  | `WIDTH`      | Write data (A) |
| `a_dout`        | out | `WIDTH`      | Registered read data (A) — **write‑first** when `a_we=1` |
| **Port B**      |     |              |             |
| `b_we`          | in  | 1            | Write enable for Port B |
| `b_addr`        | in  | `ADDR_W`     | Address for Port B |
| `b_din`         | in  | `WIDTH`      | Write data (B) |
| `b_dout`        | out | `WIDTH`      | Registered read data (B) — **write‑first** when `b_we=1` |
| **Clear**       |     |              |             |
| `clear_start`   | in  | 1            | Assert ≥1 cycle to begin zero‑clear sweep (`0..DEPTH-1`) |
| `clear_busy`    | out | 1            | High while clearing (Port A is hijacked for zero writes; Port‑B writes are masked) |
| `clear_done`    | out | 1            | One‑cycle pulse when clear finishes |

**Collision rule:** if both ports write the **same address** in the **same cycle**, the final content is **undefined** — avoid this in your design.

---

## 3) Timing & behavior summary

- **Synchronous read & write** on **posedge `clk`**.  
- **Write‑first (same port):** during a write on A (or B), `a_dout` (or `b_dout`) reflects `a_din` (or `b_din`) for that cycle.  
- **Cross‑port read during other‑port write (same cycle):** the reading port observes the **old** memory contents (read‑old across ports).  
- **Clear:** when `clear_start` is asserted, the module writes zeros across all addresses via Port A. During `clear_busy=1`, external writes are blocked (A hijacked, B writes masked). Reads are allowed and you can observe progress.  

---

## 4) Example instantiation

```verilog
module top;
  parameter WIDTH  = 16;
  parameter DEPTH  = 256;
  parameter ADDR_W = 8;     // ceil(log2(256)) = 8

  reg                  clk, rst_n;
  reg                  a_we;
  reg  [ADDR_W-1:0]    a_addr;
  reg  [WIDTH-1:0]     a_din;
  wire [WIDTH-1:0]     a_dout;

  reg                  b_we;
  reg  [ADDR_W-1:0]    b_addr;
  reg  [WIDTH-1:0]     b_din;
  wire [WIDTH-1:0]     b_dout;

  reg                  clear_start;
  wire                 clear_busy, clear_done;

  ram_dp #(.WIDTH(WIDTH), .DEPTH(DEPTH), .ADDR_W(ADDR_W)) u_ram (
    .clk(clk), .rst_n(rst_n),
    .a_we(a_we), .a_addr(a_addr), .a_din(a_din), .a_dout(a_dout),
    .b_we(b_we), .b_addr(b_addr), .b_din(b_din), .b_dout(b_dout),
    .clear_start(clear_start), .clear_busy(clear_busy), .clear_done(clear_done)
  );

  // clock/reset generation omitted
endmodule
```

---

## 5) Using the clear engine

**When to use:** before a new algorithm run (e.g., knapsack DP base row = 0).

**Sequence:**
1. Set `clear_start=1` for one cycle.
2. Wait until `clear_busy` rises, then until `clear_done=1` (one‑cycle pulse).
3. After `clear_done`, memory contents are guaranteed to be `0`.

**Note:** while `clear_busy=1`, do **not** drive writes into the RAM; the module masks them.

---

## 6) Integrating with a knapsack accelerator (Option‑A rolling DP)

- Map DP state to a **1‑D array** `dp[c]` using this RAM (depth = `W+1`).  
- Per capacity `c` (looping **downward**):  
  - Read `dp[c]` (Port A) and `dp[c - w[i]]` (Port B).  
  - Next cycle: compute `with = B + v[i]`, `without = A`, then **write back** `max(with,without)` to address `c`.  
- This achieves ~**1 update/cycle** with a small pipeline.  

---

## 7) Running the included testbench

```bash
iverilog -g2005 -o a.out src/ram_dp.v tb/tb_ram_dp.v
vvp a.out
gtkwave tb_ram_dp.vcd
```

The TB checks:
- Port‑A/B basic R/W  
- Parallel R/W (different addresses)  
- Same‑port **write‑first** behavior  
- Cross‑port **read‑old** behavior  
- `clear_start` / `clear_busy` / `clear_done` with full zero verify  
- Random stress (avoids undefined dual‑write same address)

---

## 8) Troubleshooting

- **“No such file or directory: tb_ram_dp.vcd”** → Ensure `$dumpfile/$dumpvars` are present; run the sim again.  
- **Reads look one cycle late** → That’s expected: read data is registered (sync read). Drive addresses on **negedge** in TB; data updates after **next posedge**.  
- **I want instantaneous read on address change** → That’s async read (combinational) and may not infer BRAM on all FPGAs. The provided RAM uses **registered** (sync) read for portability.  
- **Dual write same address in same cycle** → Undefined; add arbitration upstream.  

---


## 👤 Author
**Arnold Alinda**  
Master’s of engneering (Computer & Microelectronics Systems), UTM  

