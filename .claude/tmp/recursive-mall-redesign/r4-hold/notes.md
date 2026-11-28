# Round 4, feature 2: hold after release (on top of r2-b)

`build.lua` runs after r2-b's `build.lua` on the same server. Knob `MB.HOLD` (default 450).

## Circuit (real combinators, nothing simulated)
Per cell, +2 deciders in the cell's two unused slots `f[7]`, `f[8]` (+40 total, 155 -> 195):
- **HC counter** (self-loop on red, reads A1's output red = the incumbent threshold H):
  `H = 0` -> output `T = T + 1`. H > 0 (item still on the list) resets T to 0.
- **HG gate**: `0 < T < HOLD` -> `signal-H = 1e8` onto the P net (X's green input). Nothing on Q0
  (max ~2.5e6) beats it, so X cannot re-pick; the cell keeps crafting its old item. If the item
  re-enters the list inside the hold, H > 0 again and the cell never switched. 1e8 + 2e9 stays below
  int overflow. 0 changes to existing combinators; 2 short in-cell wires each.
- **HOLD = 450** = the measured switch cost (ski-rental rule: hold as long as one switch costs; if
  the item comes back within that time a whole dump + robot leg is saved, otherwise at most one
  switch worth of over-production is lost).

**Startup artifact:** a freshly built cell has H = 0, so every cell holds for 450 ticks after build
(first t10 run: 62% working, no-recipe 18%). All measured runs below use a 500-tick demand-0
pre-roll on *both* servers. The pre-roll itself was asymmetric: off refilled buffers (27% working),
on stayed held (96% no recipe). A real blueprint paste would pay this 450 ticks once.

## Results (sandbox, fresh copies, slot 6 = off, slot 7 = on)

| Run | Metric | off (r2-b) | on (HOLD 450) |
|---|---|---|---|
| 50 servers, 3600 t | working | 86% | 80% |
| | changes / fast (<=60 t) | 52 / 11 | 61 / 11 |
| | servers made / first 10 | 8 / not reached | 9 / not reached |
| 5-server batch | ticks to all 20 idle | 8400 | 10800 |
| | total changes | 218 | 272 |
| | fast changes | not measured (log overwritten per chunk) | same |
| | hoard at idle | 0 | 0 |

First (no pre-roll) pair, 3600 t: off 78% / 71 changes / 12 fast / 8 servers; on 62% / 80 / 8 / 5
(dominated by the startup hold).

## Findings
- On the sandbox the AC <-> cable oscillation barely shows in 3600 t (cable 0.08-0.29 cells), so
  the hold has little to fix there and its cost shows: more changes, lower working %, no fewer fast
  changes.
- The hold delays wind-down: every release waits 450 t before the cell can go idle, so the 5-batch
  idles 2400 t later with 25% more changes.
- Verdict for HOLD 450: no gain. Untested: shorter hold (150-225), arming the hold only for releases
  from a real item (fixes the startup artifact, needs a 3rd combinator), and the full save where the
  cable oscillation actually occurs.
