# Round 4, feature 1: adaptive buffer (on top of r2-b)

`build.lua` runs after `harness.lua`, `mask.lua`, `H.rig_off()` and `r2-b/build.lua`. Everything is
real combinators and wires built in-engine; **nothing is simulated**. The only script parts are
measurement: `MB.ad_B` reads the memory's output, and a 600-tick logger records B.

## The circuit (5 combinators added, 11 wires, all at the head row y = 102.5)

| Combinator | Inputs | Does |
|---|---|---|
| X1 decider | green: raw D (`mm` + `ms` output **green**, a new net separate from the latch's red D net) | each > 0 → each = 1 |
| X2 arithmetic | green: X1 out | each × −1 (X1 one tick late, negated) |
| M decider | red: X1 + X2 out (= the rising edge); green: step = existing `bsc` (stack ÷ 4) | each red > 0 → copy green: one step, one tick, per rising edge |
| MEM arithmetic | red: own output + M out | each + 0: the B memory, starts at 0, no cap, no decay |
| H2 arithmetic | green: MEM out | each ÷ 2 → red onto the D net (constant B/2) and green into the latch `hl` |

`bsc` no longer feeds `hl`; `hl` copies B/2 while on. The D net therefore carries D + B/2 + (B/2 if
on): the item starts when stock < missing + B/2 and stops at stock ≥ missing + B. With B = 0 it is
plain on-demand. Head goes 15 → 20 combinators (155 → 160 total).

Interpretation: the "stockout" edge is the sketch's rising edge of raw D > 0 (stock drops below
missing), not stock = 0.

## Results (sandbox, fresh copies, two servers in parallel; slot 4 = r2-b, slot 5 = r2-b + adaptive)

| | r2-b (off) | adaptive (on) |
|---|---|---|
| 3600 t, 50 servers: working | **79%** | 75% |
| recipe changes | **59** | 72 |
| changes within 60 t of the cell's last | **6** | 9 |
| servers made / time to first 10 | 7 / not reached (first at 1147) | 7 / not reached (first at 1222) |
| 5-server batch: ticks to idle | **8400** (idle in chunk 7) | **never** within 12000 (20/20 cells still busy) |
| batch: total changes | 264 | **72** |
| batch: fast changes (≤ 60 t) | 43 | **8** |
| hoard at end | 0 | 1148 |
| stock at end: server / AC / components / cable | 14 / 79 / 729 / 788 | 30 / −6 / 1004 / 606 |

B in the batch run (log every 600 ticks): cable 0 → 100 → **200** by 1200 t; AC 50 → 250 → 300 →
**500** by ~4800 t; components 100 → 150, then 250 → 800 → 1150 → **1200** at ~6600 t; server
12 → **36** at ~1800 t; electronic circuit stayed 0. **B stopped growing at ~6600 t** and held to
12000 t. In the 3600-t run: cable 150, AC 200 (still growing at the end), components 150, server 12.

## Findings

- **It kills the AC ↔ cable oscillation:** the batch wind-down goes from 264 changes / 43 fast to
  72 / 8. Cable's B settles at 200 (a full stack) and it no longer leaves and re-enters the list.
- **But a 5-server batch turns into a ~36-server one.** The rising edge of D > 0 fires every time a
  delivered item brings stock back to missing and the next request pushes it under again, so B
  grows several steps *during* any batch, not only on a real stockout. B does self-limit (settled
  by ~6600 t), but at levels sized for the batch: server 36, AC 500, components 1200. Then the mall
  must build all of that before it idles: still 100% busy at 12000 t, 30 servers in stock for 5
  demanded, and B never shrinks.
- The 3600-t demand-on run is slightly worse (75% vs 79%, 72 vs 59 changes): early growth moves
  cells onto blank tech cards (2.3 vs 1.1 average cells) and away from components.
- Suggested next steps (not built): count a stockout only when stock ≤ 0 (needs raw stock, which
  `hd.neg` already has on its own net), or grow only for intermediates (not the demanded item),
  or a slow decay of B while D ≤ −B.
