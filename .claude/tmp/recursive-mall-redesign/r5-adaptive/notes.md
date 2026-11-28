# Round 5: adaptive buffer with the stockout edge (on top of r2-b)

`build.lua` loads after `harness.lua`, `mask.lua`, `H.rig_off()` and `r2-b/build.lua`. It is round 4
with one changed combinator and one extra wire. Everything is real combinators and wires built
in-engine; **nothing is simulated**. The only script parts are measurement (`MB.ad_B`, the
600-tick B logger, and a change counter that reads `H.state` after each chunk).

## The changed edge circuit

- **X1 decider** was `each(green rawD) > 0 → each = 1`. It is now
  `each(green rawD) > 0 AND each(red) = 0 → each = 1`.
- **New wire:** `hd.neg` output **red** → X1 input red (4 tiles). `hd.neg` outputs −stock only for
  items with stock > 0 (`hd.pos` filters out the rest), and its red output had nothing on it. So an
  item that is absent on X1's red input has stock ≤ 0. That confirms round 4's note: raw stock was
  already on its own wire.
- X2 (one-tick-late negation), M (edge × step), MEM (B), H2 (B/2) and the latch wiring are
  unchanged. B grows by stack ÷ 4 on each rising edge of (stock ≤ 0 AND D > 0). It starts at 0, has
  no cap and no decay. The latch turns on at 50 % of B and off at 100 %.
- Count: still **5 combinators** added at the head (155 → 160 total), and **12 wires** (round 4
  had 11).

## Results (sandbox, fresh copies, run in parallel: slot 4 = r2-b, slot 5 = r2-b + adaptive)

| | r2-b (off) | r5 adaptive (on) |
|---|---|---|
| 3600 t, 50 servers: working | 81% | 82% |
| recipe changes | 58 | **45** |
| changes within 60 t of the same cell's previous change | 7 | **1** |
| servers made / time to first 10 | 8 / not reached (first at 1382) | 8 / not reached (first at 1407) |
| 5-server batch: ticks to idle | **8400** (20/20 idle in chunk 7) | **never** within 12000 (0/20 idle, 97–100% working) |
| batch: total changes | 197 | 55 |
| batch: fast changes (≤ 60 t) | 16 | 4 |
| hoard at end | 0 | 1050 |
| stock at end: server / AC / components / cable | 14 / 79 / 707 / 806 | **24** / −6 / 902 / 526 |

Every chunk had its own tag (`b1`…`b10`), and the change totals were summed across chunks.

**B trajectory during the batch** (logged every 600 t from the start of the batch):

| item | B |
|---|---|
| cable | 0 → **250** by 600 t, then flat |
| server | 12 → 24 → **36** by ~1800 t, then flat (5 were demanded) |
| components | 50 → 100 (600 t), flat until ~4800 t, then 700 → 1300 → **1850** by ~6000 t, then flat |
| AC | 50 → 250 → 350 → 450 → 500 → 550 → 600 → **650** at 11400 t, **still growing** |
| electronic circuit | 0 |

In the 3600-t run, B ended at cable 50, AC 150, components 100 and server 24. Server grew while
50 were requested.

## Why the stockout edge does not fix it

A stockout here is not a single event. While the item is in demand, stock sits at or around 0.
Each item that arrives (stock 0 → 1) is drawn off again at once (1 → 0) while D is still > 0. That
re-arms the edge and fires it again:
- server: each finished server goes into the network, and the trigger requester takes it;
- components and AC: the assemblers draining them hold the stock at 0 or below (the network
  shows −38 components and −12 AC) for thousands of ticks.

So B still grows once per item that passes through the network, not once per stockout. The levels
are about the same as round 4's (server 36, AC 500 → 650, components 1200 → 1850), and the mall is
still fully busy at 12000 t building a 24-server stock for a 5-server order. The change rate is
much lower (55 vs 197 total, 4 vs 16 fast; and 45 vs 58 in the 3600-t run), but that only
reflects that the mall never winds down.

## Verdict

The stockout edge (stock ≤ 0 AND D > 0) works as built, but it does not stop the runaway: the edge
fires on every pass through zero during a batch, so a 5-server batch still settles B at about
36 servers, and the mall never goes idle within 12000 ticks. Next step, not built: re-arm the edge
only after stock has refilled to B/2 (an SR latch per item, set by the edge and reset when
stock ≥ B/2). That would give one step per drain-and-refill cycle. The other option is decay.
