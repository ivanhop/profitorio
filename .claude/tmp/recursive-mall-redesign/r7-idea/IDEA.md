# r7 idea: central dispatcher with grace and work-weighted scores

Proposal only. Nothing here is built or measured. Base: `design-c/`. Borrowed: grace from `r3-grace/`.

## 1. The design

**In plain words.** The head keeps C's per-item cell bitmask M and hands out free cells one at a
time by D'Hondt. Three things change:

1. **Score by work, not count.** The score is `N × T / (A+1)`. T is how many cell-ticks one item of
   X takes, measured live from the cells. Advanced circuits (AC) take 8× the ticks of cable per
   item, so they now weigh 8× as much.
2. **Grace at the head.** A grace mask G marks cells that have not yet finished a craft since they
   were assigned. The backstop and the rebalancer may only release bits in `M AND NOT G`. A cell is
   never moved before its first craft. One exception: the item leaving the list still frees it, as
   in r3-grace.
3. **Free cells always get a recipe while there is demand.** The 1800-tick cooldown no longer
   excludes an item. It only ranks it below every item that is not cooling down.

**Per cell: 5 combinators** (C has 3)
- C1, C2 and C5 stay as in C: the recipe from `M AND 2^k`, the V bus (1, or 1025 when starving), and
  the chest requests.
- **CF (new, decider):** reads the output inserter's hand in pulse mode on green and C1's recipe on
  red. Where red ≠ 0 it copies the green count onto the **I bus (green)**. It counts products only:
  the ingredients dumped by a switch leave through the same inserter, but they are not the recipe's
  item, so they are dropped.
- **CG (new, decider):** when the assembler's recipe-finished pulse `signal-R` > 0, it outputs
  `signal-K = 2^k` onto the I bus's **red** wire. That bus is the craft bitmask.
- Assembler: add read-recipe-finished (`signal-R`) on green, as r3-grace does. C5 already passes
  `signal-W` to the chests, and virtual signals set no request.

**Head: C's 32 + 2 constants, plus about 31**
| Block | What it carries | Count |
|---|---|---|
| Epoch clock | `signal-E`, counts 0..2047 | 1 |
| Work accumulator Wk[item] | Adds `A − S` (working cells per item, decoded from V by C's Adec/Sdec) every tick. Halved at each epoch (arith ÷−2, gated by E = 0) | 4 |
| Item accumulator Pk[item] | Adds the I bus green (products per item). Halved the same way | 3 |
| Prior | `ONE × 4·T0` added to Wk, `ONE × 4` added to Pk, on the division's input wires (T0 = 60 t/item) | 2 |
| T16 = 16·(Wk+prior)/(Pk+prior) | Ticks per item, ×16 for integer resolution | 2 |
| Work = N × T16 × (1 + U/τ) | U = urgency, below | 2 |
| Urgency U[item] | +1 per tick while the item is latched with stock ≤ 0. Halved at each epoch. τ = 1024 | 5 |
| Grace mask G (`signal-G`) | `G += (Asum AND NOT G) − (G AND (K OR Ex))`. Asum = the bit just assigned (sum of Amul's output) | 6 |
| Grace expiry Ex | Snapshot of G at each epoch. `Ex = G AND snapshot`, so a cell in grace becomes releasable 2048–4096 t after assignment if it never crafts | 3 |
| Mr = M AND NOT G | Feeds LB/Mneg instead of M, so the backstop and the rebalancer only see releasable bits | 1 |
| Cooldown as a rank | Elig passes cooling items too, but non-cooling items get +2^26. The offset is removed before the rebalancer's 2× test | 2 |

Score stays `Work/(A+1)` in C's Score arith; only its green input changes from N to Work.
**Total ≈ 100 + 63 = 163 combinators + 2 constants.** r3-grace has 195, C has 92.

Wires: the I bus needs a green and a red wire across the bottom, relayed through the poles at
(−231.5,137.5) and (−225.5,137.5). All wires stay ≤ 9.75 tiles.

Knob, default off: **grace on unlatch.** For unlatched items, the memory's keep-mask uses `M AND G`
instead of 0, so a cell mid-switch keeps its item until its first craft (2 combinators). Run as a
variant (§5).

## 2. Claims and mechanisms

Ticks per item at cell speed 1.05, from the bench recipes (`bench_design-c.json`): beacon 857,
AC 114, components 57, cable 14.3. The ideal split is AC 9.1 / components 4.6 / beacon 3.4 /
cable 2.9.

| # | Claim (50-beacon bench) | Mechanism |
|---|---|---|
| C1 | **AC ≥ 7.5 cells** on average until delivery (C 3.8, grace 6.7) | T makes one AC item weigh 2× a component and 8× a cable item. C weighted them equally |
| C2 | **Components ≥ 3.5, cable 2–4, beacon ≤ 5** | Urgency lifts whichever ingredient is stocked out (see risk R1) |
| C3 | **No recipe < 15%** (C 48%, grace 11%) | Free cells never wait on a cooldown. Far fewer abandoned switches, each of which costs ~450 t with no recipe |
| C4 | **≤ 250 recipe changes, ≥ 60% reaching a craft** (C 396/40%, grace 350/32%) | Only an unlatch or grace expiry frees a cell before its first craft |
| C5 | **Switching ≤ 12%** (C 8%, grace 16%) | Fewer and stable changes |
| C6 | **50 delivered ≤ 20 000 t (≥ 62% of perfect)**; stretch 18 000 (grace 22 137) | C1–C4 together: useful time from 23% (C) and 49% (grace) to ≥ 55% |
| C7 | **All idle ≤ t(50) + 4000 t** (grace +3454, C never idle) | Unchanged list and keep-mask. Grace never blocks an unlatch (knob off) |
| C8 | **≤ 110 MJ per beacon, robot items ≤ 1.7× ideal** | Churn is what costs (robots are 72–92% of the energy), and C4 cuts the churn |

## 3. Crafting time without a recipe table

- **What is measured:**
  - **Wk[item]**: working cell-ticks. `A − S` per tick, where S counts cells that have a recipe
    but are not working. Starvation, a full output and a switch therefore add nothing.
  - **Pk[item]**: products, from the output inserters' hand pulses. Productivity bonus items are
    counted, and so is the recipe's product count (cable 2, components 4).
- **By whom:** each cell reports raw events (C2's V bus, CF's I bus). The head does all the
  arithmetic, per item with `each`.
- **Window:** both accumulators are halved every 2048 ticks, so they weight the last ~4000 ticks.
  Speed, modules and beacons are pooled across the cells, so a module change shows up within about
  two epochs.
- **Before the first measurement:** a prior of 4 items at 60 t/item; after ~4 real items the
  measurement dominates.
- **Scale:** Wk·16 ≤ 20 × 4096 × 16 ≈ 1.3e6; Work for 3000 components (T16 = 912, urgency ×8)
  ≈ 2.2e7. Both fit int32.

## 4. Risks and unknowns

- **R1 (unsure, the main one): N is cut off by the chest requests.** An intermediate's N is only
  what its consumers' chests ask for. That is 8 crafts' worth per consumer cell (assumption: each
  of the 4 chests requests ×K = 2, as C5 is wired to all four). The root's N, by contrast, is the
  whole batch.
  - My fixed-point estimate without urgency (ignoring stock and B): beacon 5, AC 11,
    components 2, cable 1.4. The root is over-weighted, components starved.
  - Urgency (integral action) is the correction; it may overshoot or oscillate on the epoch
    period. Runs 2 vs 3 in §5 isolate it.
- **R2: unverified wiring.** Assumptions:
  - Each cell's output fast inserter (one of the 102 in `layout-0.2.7.json`, into the
    active-provider chest) can be wired, and in pulse mode reports exactly one item type per swing.
  - The poles' green wire is free for the I bus.
  - A decider with `each` conditions can copy only its green input.
- **R3: G's update relies on bit sets not overlapping.** A craft pulse and a new assignment of the
  same bit in the same tick could leave a stale bit. A stale bit only protects a cell, and expiry
  bounds it to 4096 t.
- **R4: the cause of C's unassigned cells is a hypothesis.** I read it as abandoned switches
  (239 of 396 never crafted) plus the 1800-tick cooldown blocking recipients. Neither is measured
  directly.
- **R5:** the cooldown as a rank may herd free cells onto a cooling item; grace bounds each move to
  one craft. **R6:** a cell starved in grace waits up to 4096 t (e.g. an unmasked ingredient).
- **R7: C never went idle in 54 000 t, cause unknown.** C7 depends on finding it (run 0).
- **R8: one run per design so far;** r6 varied 30–45 delivered between copies.

## 5. Test plan (`bench/`, 50 beacons, sandbox, 54 000-t cap)

**Build in stages.** Each stage is a `CFG` flag in one `r7/build.lua`, so a run differs from the
next by one mechanism.

| Run | Config | Answers |
|---|---|---|
| 0 | design-c with `T_REL = 600`, everything else as C | R4/R7: is the cooldown why cells sit unassigned? Log the free-cell count (ΣM popcount) every 60 t, and the latched items at the cap |
| 1 | r7 grace only (G, Mr, cooldown as a rank), score N/(A+1) | C3, C4 on their own |
| 2 | 1 + T (score N×T) | C1 on its own |
| 3 | 2 + urgency (the full r7) | C2, C6, C7, C8 |
| 4 | 3 + grace on unlatch | Whether protecting switches through an unlatch beats the extra surplus |
| ref | r3-grace, design-c | Same-day baselines on fresh copies |

- **Repeats:** 3 fresh copies for run 3 and each ref, 2 for runs 0–2 and 4: **17 runs**, as
  parallel pairs on separate slots (r7 against r3-grace on each pair).
- **Pass (means):** run 3 beats r3-grace on t(50) and on MJ per beacon by ≥ 5%; every r7 copy beats
  the best r3-grace copy on t(50); C1–C8 hold.
- **Extra logging** (harness only): T16 per item every epoch (check against 857/114/57/14.3 × 16),
  U per item, G popcount, releases blocked by grace.
- Then a 5-server batch to idle, as in round 6.
