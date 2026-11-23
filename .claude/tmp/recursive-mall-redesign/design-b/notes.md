# Design B: helpers walk down the recipe tree

`build.lua` rebuilds the whole design on a fresh copy, after `harness.lua` and `H.rig_off()`. It
takes about 1 s. `blueprint.txt` is the mall block (y 100..138.9, the rig assembler is left out).
It imports cleanly: 466 entities. The optional `MB = {...}` before loading sets the knobs:
`BUDGET` 120, `K` 2, `SP` 3, `BDIV` 4, `NCH` 4, and `BLIND` (the comparison variant).

## As built

The R chain is gone. Every cell reads global buses, and races are avoided with a **slot clock**:
cell k may change only on the tick when `signal-Z = -3k`. The clock period is 101 ticks, so each
cell gets one decision per ~1.7 s. Slots are 3 ticks apart, longer than a change takes to reach
the buses.

**Per cell: 7 combinators** (was 9). They sit in the old slots, so the footprint is unchanged.

| # | Combinator | Job |
|---|---|---|
| S | selector, max | candidate P = top of (Q0 bus + own Tb) |
| X | decider | at its slot, if P > H: emits P (value 1) and `signal-X = -1` |
| A1 | arith, each(red) × each(green) → H | H = Y[own item], the incumbent's threshold |
| L | decider latch | holds the item (value 1) unless X fires; output red → recipe, green → O bus |
| K | decider | budget: `signal-B` += working − 1 (read-working is `signal-B`); reset on X |
| T | decider | when B ≤ −BUDGET: each own ingredient whose Q0 > 300000 (on F) gets +1e6 → Tb; same output on red → HELP bus |
| Req | arith | each ingredient × K → the 4 requester chests (trash-unrequested on) |

**Head: 15 combinators** plus the mask and a constant `signal-dot` = 50000 (the idle candidate).
Ten of them are new, in the free rows y 100–102 (x −228..−216). Three new medium poles at y 138.5
carry O and HELP across the bottom. Total: 155 combinators, against 199 before.

Head signals:
- D = masked missing − masked stock. Hysteresis latch: on when D > 0, off once there is a surplus
  of B = stack/4.
- **Q0 bus (red).** The F class is 500000 + min(F,999) − 1000·cells + HELP/100. Unstaffed F items
  get +1e6 (the R class). It also carries the clock and the idle candidate.
- **Y bus (green).** It is 2e9 when the item has a sole holder, 999999 when it has several, and 0
  when the item is off F. So: a sole holder never moves (it is the owner). A shared helper moves
  only to an unstaffed item or to a boosted ingredient. An empty or stale cell takes anything.
- **O bus (green).** Every latch at value 1, which gives cells per item.
- **HELP (red).** Exhausted cells advertise their short ingredients, and free cells prefer them.

Walk-down costs 1 decider (T). Compared with a blind re-pick, it is one extra condition on T
(`each(ingredient) > 0`). HELP costs nothing per cell: it is T's second output colour plus 1 head
arithmetic. The ingredient filter itself is simple. Most of the effort went into making changes
race-free and sticky (S, X, A1, L).

## Scorecards (fresh copy, standard protocol, final build)

| Run | Working | Recipe set, not working | No recipe | Changes | Hoard |
|---|---|---|---|---|---|
| S1 | 28% | 58% | 13% | 44 | 372 |
| S2 | 72% | 22% | 6% | 7 | 708 |

Baseline S1: 10 / 6 / 84 / 68 / 4627. Repeat runs of S1 gave 24–28%. Repeat runs of S2 gave
72–95%. S1 is capped by robots: the first ingredient delivery takes 200–300 ticks, even for
components whose inputs are in stock. S2 stays busy by design: the hysteresis keeps the 50-server
batch on F until stock ≥ B. The server needs steel beams (not on the mask), so it never finishes.

**Convergence, 3 × 1200 ticks of S1 demand.** Walk-down against blind re-pick (`BLIND=true`: an
exhausted helper takes the least-staffed F item, no HELP):

| | Seg 1 | Seg 2 | Seg 3 | Changes |
|---|---|---|---|---|
| walk-down | 48% | 99% | 100% | 62 / 0 / 0 |
| blind | 23% | 43% | 56% | 92 / 65 / 31 |

Walk-down settles in about 20 s: 18 components, 1 AC, 1 server (sole). After that, no changes.
Blind is still churning after 60 s, with about 5 cells parked on the unbuildable server.

**Batch then idle** (server request cleared first). Power-switch ×20:
- 0–1200 ticks: 34% working, 24 crafted.
- Request cleared, 1200–2400: tail batch to the buffer.
- 2400–3600: **0% working, 100% no recipe, 0 changes, chest hoard 0**. Every latch holds
  `signal-dot`. Stock ended at 17 power switches, the buffer.

## What failed along the way

- **The chained R list needs 3–5 combinators of delay per cell.** The claim takes 4 ticks to
  appear (R → Q → S → X → L). Without exact alignment, a new item ripples down every free cell.
  That is why the design moved to global buses plus the slot clock.
- **Using the selector output as the cell state oscillates.** The S → bonus → S loop is 2 ticks,
  so any one-tick blip turns into a period-2 flip. The fix was a real latch (1-tick loop) that
  changes only on X.
- **Owner/helper by threshold.** The helper bonus and the owner bonus cannot be ordered against a
  T boost when both come from the same value. The fix: sole holder = owner, read from the O bus at
  the head (the Y bus).
- **The "fewest cells" pick sent freed cells back onto the starving server.** They then had to
  walk down again. HELP fixed it: S2 went from 60% to 84–95%, and changes from 12 to 0–7.
- **HELP fed itself:** an item stayed on Q0 after leaving F. Fixed by using a 500k F class with a
  300k threshold in T.
- **B = 1 stack** kept AC on F for a 200-item tail long after any demand. B = stack/4 (BDIV)
  fixed it.
- **One requesting chest per cell** (×4 per request) did not help S1. Kept 4 chests.

## Open problems

- **Every recipe change costs 100–360 ticks of "no recipe".** The leftover ingredients go to the
  assembler's dump inventory, and the single output inserter clears it at about 2 items per
  30 ticks. This dominates the cost of any re-pick, and it is why walking straight to the
  bottleneck beats blind trial moves.
- **The fallback is "stay".** An exhausted helper whose ingredients are off the mask (raw plates)
  never moves. C10/C11 sat 600 ticks waiting for silicon that was in flight. That is robot latency,
  not a shortage.
- **The budget never recovers while working.** Once exhausted, a helper walks at the next blip of
  any ingredient shortage.
- **S1 is bounded by the logistics network**, not by the controller.
- **The rebuild discards the old recipes**, so S1 pays dump time on cells that were already busy.
