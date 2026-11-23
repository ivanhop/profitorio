# Design C: central bitmask dispatcher

`build.lua` builds it on a fresh colin0.2.7 copy. Run it after the harness and `H.rig_off()`. Knobs
are in `CFG`, block 1. `blueprint.txt` is a 400-entity export of the mall (the rig assembler is
stripped). A paste test passed: on a fresh copy, the old combinators were removed, the blueprint was
built with `build_blueprint` at position (-230,120), and the ghosts were revived. Wires and
settings on existing entities were restored, and the mall ran at 97% working in steady state.

## Design as built

There is no daisy chain. The head owns one memory, **M[item] = bitmask of the cells assigned to that
item** (bit k = cell C(k+1), in `H.cells()` order). It broadcasts M to all cells on one red bus.
Because a cell's bit lives in at most one item, the cell can extract its recipe with a single
AND, and there is no signal-order ambiguity.

**Cell: 3 combinators** (was 9)
- C1 arith `each AND 2^k`: one item, value 2^k, sent to the assembler on red (set recipe).
- C2 decider: if recipe set and `signal-W` (read working) = 0, output `each = 1025`; else output
  `each = 1`. This uses `else_outputs`. The result goes onto the shared **V bus**, so at the head
  V[item] = cells + 1024 × starving cells.
- C5 arith `ingredients × K` → the 4 chests (K = 2 crafts per chest). Chests have trash-unrequested on.
- Assembler: input red only, output green only (read ingredients + read working).

**Head: 32 combinators + 2 constants**
- List (right, by roboports (-213,133) missing / (-213,137) contents): stock>0, ×-1, stack-size(mask),
  latch, Nout. Hysteresis as in research.md §4.1: on at D>0, held while D>-B, B = 1 stack.
  Output N = D+B. The latch flag is 2^28, fed back.
- Memory: `M' = (M + Δ) AND K` (each AND each). K = ALL (2^20-1) for latched items, so unlatched
  items clear and stray bit 20 is stripped. Δ = assign bit (+) or release (−lowbit).
- Free cell: `lowbit(ΣM + 1)` via X = ΣM+1, Y = −(ΣM+1), X AND Y. It is 2^20 when no cell is free.
- Clock period 20. Every 5 ticks: the target is the max over eligible items of **D'Hondt score
  N/(A+1)** (A from the V bus, +1 per latched item from ONE). The lowest free bit goes to the target.
- Starvation backstop (per item, pooled): Acc[item] += starving cells. When Acc ≥ 900·(A+1) and
  A ≥ 2, release the item's lowest bit. The release is pulse-exact because the memory resets.
  Owners are protected, since an item never drops below 1 cell this way. Released items get a
  1800-tick cooldown as recipients.
- Rebalancer (once per 20 ticks, only when no cell is free): victim = the min (score+1) among items
  with ≥2 cells. Release its lowest bit if best eligible score > 2 × victim. The victim also gets
  the cooldown. This covers preemption: a new ingredient with 0 cells scores N/1 and steals a cell.
- Signals used: each, C (clock), X/Y/B (free bit), H (rebalance compare), W (working).

**Footprint**
- The old head area (x -224..-221, y 103..107) is now empty.
- The head sits in freed slots of cells C10–C14, plus the empty strip at y 137..138
  (x -244..-233 and -225..-216).
- Relays use existing entities: pole (-231.5,137.5) and pole (-225.5,137.5) carry M (red), and the
  substation (-227,138) carries V (red) and N (green).
- All wires are ≤ 9.75 tiles. Longer wires (combinator→substation, 14 tiles) work through the API,
  but `build_blueprint` drops them.
- Total: 92 combinators + 2 constants (was 186 + 2).

## Scorecards (fresh copy, rig off, K=2)

| Run | working | recipe, not working | no recipe | changes | hoard |
| --- | --- | --- | --- | --- | --- |
| Baseline S1 | 10% | 6% | 84% | 68 | 4627 |
| **S1** (600 t) | **35%** | 50% | 15% | 24 | 742 |
| **S2** (600 t, demand cleared) | **87%** | 11% | 2% | 1 | 958 |
| Convergence, demand on, 3600 t | 78% | 18% | 4% | 26 | 860 |
| T3: 400 small-lamp, server demand cleared, 1800 t | 56% | 38% | 6% | 31 | 572 |
| T1: no demand, 1800 t after a components batch | all 20 cells idle, hoard 0 | | | | |

- Earlier builds gave S1 34–39% across runs, so variance is about ±4 points.
- S1: by tick 87, 20 assignments (one per cell). The 4–7 extra changes are cable batches and rebalancing.
- S1 losses:
  - Robot first delivery takes 180–700 ticks after an assignment.
  - C1 and C2 sit with no recipe for 400–580 ticks. Their old recipes (server, AC) were changed,
    and the engine first empties the leftover ingredients through one output inserter.
- S2 stays busy because the latch holds server until stock ≥ 1 stack (50) (§4.1 semantics). The
  rival designs behave the same way.
- Convergence split: 12.8 components, 5.2 AC and 1.2 server cells. That made 158 components crafts,
  70 AC crafts and 7 servers.
- T1: the save has outside demand for components. All 20 cells took it, the batch ended at stock
  403 (B = 200), the cells dropped their recipes over ticks 288–510, and the trash emptied the chests.
- T3 shows cable getting cells through preemption and rebalance: 0.5–2.9 cable cells.

## What failed along the way

- **Per-cell starvation budget of 300 starved ticks (v1, 5 combinators per cell)**: fresh cells were
  released before their first robot delivery arrived (180–700 ticks), which caused churn.
  Replaced by a pooled budget of 900·(A+1).
- **Eligibility "not all of the item's cells are starving"**: new cells always starve at first,
  so the fill stalled waiting for robots. Dropped.
- **No rebalancer** (T3 v2): all 20 cells went to lamps, cable appeared after cable stock ran out,
  and only one cell per ~1000 ticks moved over (23% working). With the rebalancer: 56–58%.
- **No cooldown for rebalance victims**: the server cell bounced server→cable→server→components
  (7 changes in S1). Victims now get the release cooldown.
- **Clock period**: 10 ticks gave S1 25%. 5 ticks between assignments gave 35–39%.
- K=3 gave +2 points working in convergence (82%) for +60% hoard. Kept K=2.

## Engine facts learned (2.1.24)

- Arithmetic `each op each` (red vs green) and decider `each cmp each` both work per signal.
- Decider `else_outputs` work per `each` signal.
- Int32 multiplication wraps.
- Wire reach between a combinator and a substation is the larger of the two (14 tiles accepted),
  but `build_blueprint` + revive dropped those wires. Keep wires ≤ 9.75.
- `entity.input_networks` / `output_networks` exist on assemblers.
- A recipe change with ingredients left in the machine leaves it with no recipe until the output
  inserter empties them. This takes several hundred ticks, and is the dominant cost of any reassignment.

## Open problems

- **Ratio comes from N (=D+B), not from measured craft speed.** A cheap, fast ingredient (cable)
  has small chest requests, hence a small N, so it gets too few cells. The lamp cells starve for
  cable, and only the rebalancer and starvation release correct it, slowly.
- Steel beam and K2 parts are not on the mask, so those intermediates are never built.
- Robot delivery latency (silicon for C19/C20 took a whole run) and dump-inventory clearing
  dominate S1. Neither is a circuit issue.
- Several cells may change on one rebalance pulse while the A readback lags about 10 ticks.
  Mild overshoot is possible.
