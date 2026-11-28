# Round 6: adaptive buffer that grows once per stockout event (on top of r2-b)

`build.lua` loads after `harness.lua`, `mask.lua`, `H.rig_off()` and `r2-b/build.lua`. It is round 5
plus a re-arm latch. Everything is real combinators and wires built in-engine; **nothing is
simulated**. The only script parts are measurement: `MB.ad_B` reads B and the latch, and a 600-tick
logger records them (`L` after a value means the latch is set, so the item is disarmed).

## The latch circuit

B now grows on the **rising edge of a per-item latch L**, not on the rising edge of X1.

- **X1 decider** (as in r5, but outputs K = 1,000,000): green rawD > 0 AND red (−stock, present
  only when stock > 0) = 0 → each = K. That is the stockout: stock ≤ 0 while there is demand.
- **Q arithmetic (new):** each(green: B/2 from H2) − each(red: stock from `hd.pos`, stock > 0 only)
  → B/2 − stock.
- **L decider (new), the SR latch:** green = K·X1 + B/2 − stock (Q out and X1 out on one net); red =
  its own output.
  `green > K/2` (set: only X1 can reach it) OR (`red > 0` AND `green ≥ 0`) (hold while stock ≤ B/2)
  → each = 1.
  It resets once stock > B/2, which re-arms the item. While it holds, a further stockout cannot fire
  again because L is already 1.
- **X2** now negates L one tick late (it reads L from L's red self-loop). The edge net is L out
  green + X2 out green, so M gets 1 only on the tick L rises.
- **M** reads the edge on green and the step (stack ÷ 4, now `hd.bsc` output **red**) on red. MEM
  (B) and H2 (B/2, which feeds `hl` and the D net) are unchanged from r5.
- **The first event, when B = 0:** B/2 = 0, so the hold condition `0 − stock ≥ 0` means stock ≤ 0.
  Re-arming needs stock ≥ 1, not merely ≥ 0. Re-arming is always strict (stock > B/2), so an item
  sitting at 0 never re-arms by itself. After the set, B/2 jumps by step/2 at once, so the refill
  target is the new B/2.
- **Count:** 7 combinators at the head, 2 more than r5 (155 → 162 total). 17 wire segments, every
  hop ≤ 9.75 tiles (`MB.net` asserts this). The combinators sit in a row at y = 102.5, from
  x = −222 to −234. A single combinator is not possible here: L needs set, hold and B/2 − stock on
  two wire colours, and every free output colour at the head carries +stock, not −stock, so Q is
  required.

## Results (sandbox, fresh copies, slot 4 = r2-b, slot 5 = r2-b + r6)

| | r2-b (off) | r6 latch (on) | r5 (on), for reference |
|---|---|---|---|
| 3600 t, 50 servers: working | 80% | 77% | 82% |
| recipe changes | 60 | 82 | 45 |
| fast changes (≤ 60 t, same cell) | 8 | 11 | 1 |
| servers made / time to first 10 | 8 / not reached (first 1381) | **9** / not reached (first **1046**) | 8 / – (1407) |
| 5-server batch: ticks to idle | 8400 (chunk 7) | **8400** (chunk 7) | never (12000) |
| batch: total changes | 208 | 202 | 55 |
| batch: fast changes | 23 | 16 | 4 |
| hoard at end | 0 | 0 | 1050 |
| end stock server / AC / components / cable | 14 / 107 / 643 / 676 | 14 / 95 / 707 / 782 | 24 / −6 / 902 / 526 |
| second 5-server batch | served from stock, 0 changes, idle | served from stock, 0 changes, idle | – |

The off run and the on run for the 50-server case ran in parallel. The off batch was rerun alone,
after its first copy was orphaned. Every chunk had its own tag (`b1`…, then `c1`… for the second
batch).

## B trajectory during the batch (every 600 t)

| item | B |
|---|---|
| server | 12 (set at once, latched until ~4400 t), then **flat at 12** |
| AC | 50, latched until ~6800 t, then **flat at 50** |
| components | 50, latched until ~6200 t, then 100 (a second real drain after the refill), **flat** |
| cable | 0 → 100 by 600 t, 150 at ~7400 t, **flat** |
| electronic circuit | 0 |

B stops in every case: 1 to 3 steps per item over the whole batch, against 3 (server) to 37 (AC)
steps in r5. In the 50-server run B ended at cable 150, AC 50, components 50 and server 12, all
latched from the first stockout onwards.

The second batch says little: r2-b itself leaves 14 servers in stock, so clearing the trigger chest
was served from stock (14 → 6) in both copies, and the mall stayed idle.

## Verdict

The re-arm latch does what the spec asks: one growth step per drain-and-refill cycle. B settles
small (server 12, AC 50, components 100, cable 150) and stops. The 5-server batch idles at 8400 t,
the same as r2-b, with no hoard, where r5 never went idle. Against r2-b the gain is modest: batch
fast changes 23 → 16 and total changes 208 → 202. In the 50-server run it reaches the first server
sooner (1046 vs 1381) and makes one more (9 vs 8), but changes rise (82 vs 60, 11 vs 8 fast) and
working is 3 points lower. The buffer no longer runs away, but at these small B values it barely
damps the oscillation either. A larger step, or growth for intermediates only, is the next knob to
try.

## Blueprint

`blueprint.txt` (paste string) / `blueprint.json` (entities): r2-b + r6, built on a fresh sandbox copy
and exported over x -247..-212, y 99.5..139. 474 entities, 632 wires, no circuit wire over 9.75 tiles.

- **Fixed 2026-11-28.** The first export started at y 101 and dropped the head's top row (y 100.5):
  bst, hl, c1, c2, the clock and help. Without the clock no cell ever picks, so a paste did nothing.
- **Relay pole moved** to (-221.5,103.5) in `r2-b/build.lua`. At (-220.5,103.5) it overlaps the
  contents roboport (-219,105): a script can place both, a paste cannot, and the head lost its stock.
- **Paste-tested:** cleared the block on a sandbox copy, `build_blueprint` + revive. All 474 entities
  placed, no collisions, nothing missing.
- B's memory is not part of a blueprint, so B starts at 0 after a paste, the design's own start state.
