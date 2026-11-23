# Design A: research.md §4, as built

`build.lua` builds everything on a fresh copy: load `harness.lua`, pipe in `build.lua`, then
`/silent-command H.rig_off() rcon.print(A.build(20))`. `A.export()` returns the blueprint string
(`blueprint.txt`: 617 entities, 311 combinators). Note: `helpers.write_file` without a player index
writes nothing on these headless servers, so `H.export`/`H.report` change logs never reach disk. Print over
RCON instead.

## As built

**Head (11 combinators).** Missing M and stock S (stock > 0 only), both masked: D = M − S on green, and
E = D + B on red. B = stack size ÷ `A.BDIV` (selector, then an arithmetic combinator). The hysteresis decider
`HL` turns an item on at D > 0, holds it while E > 0 (D > −B), and outputs 2^20 per item onto its own red
input. `FO` outputs **F = E + 2^20** for the items that are on, onto the green F bus. `RH` outputs
**R = 2·F** (≥ 2^21) onto the start of the chain. `CF` counts F and puts `signal-N` = |F| on the F bus.

**Cell (15 combinators: 14 plus a constant).** Values encode the role, so no flag signals are needed.
ST (red) holds the latched item: an owner's value is ≥ 2^21 (copied from R), a helper's is in
[2^20, 2^21) (copied from F). ST also carries `signal-C` = the budget, which is ≤ 0.

| Combinator | Job |
|---|---|
| SELR | max of R_in → owner pick |
| SELF | F[`signal-X`] → helper pick (the index signal is excluded from the sort; measured) |
| TAKE | the no-owner state takes an R pick (this is also the preempt). An empty state takes an F pick when R is empty |
| LATCH | an owner holds while its item is on F. A helper holds while its item is on F, no owner pick has arrived, and C > −budget |
| PASS + DLY1 + DLY2 | R_out = R_in minus the ST items. R is delayed 2 ticks so the removal lands on the tick the claim appears (3 ticks per cell, 60 ticks over 20 cells) |
| BUDGET | while helper **and the recipe is set**: C += working − 1. Reset otherwise |
| LEAVES | L −= 1 when C = 2 − budget and the cell is not working. That is exactly once per leave, and early enough that the next pick already uses the new index |
| KC + MOD | index = (720720 + cell + L) mod \|F\| |
| COUNTER, DIVREN, HOLD | working-tick counter (reset on `signal-P` = craft finished or no recipe), 300 ÷ T, sample-and-hold N |
| MULT | ingredients × N → all 4 chests. Ingredients ×1 are also wired straight to 2 chests, so total = 1200/T + 2 crafts |

Assembler: set recipe from red (ST), read ingredients / working (`signal-C`) / finished (`signal-P`) to
green (AG). L and C share AG with the ingredients, and the chests ignore virtual signals.

**Footprint.** Old cell and head zones, plus the head row y 100.5–102.5. Right extras: x −213…−204,
y 103…130 (east of the roboports). Left extras: x −258…−248, y 111…142. The F bus crosses to the left
column on the existing medium poles at y ≈ 101–108. R crosses at the bottom on poles (−220.5,135.5),
(−225.5,137.5), (−231.5,137.5) and (−238.5,135.5). There are no new poles.

## Scorecards (fresh copy, budget 600, BDIV 10, S1 started on the build tick)

| | working | recipe not working | no recipe | changes | hoard |
|---|---|---|---|---|---|
| Baseline S1 | 10% | 6% | 84% | 68 | 4627 |
| **S1** | 4% | 90% | 6% | 21 | 32 |
| **S2** | 32% | 59% | 9% | 11 | 157 |
| S1 over 3600 ticks | 52% | 39% | 9% | 88 | 426 |

Targeted tests:
- **Sweep (S1 / S2 / 3600-tick S1, working % and changes).**
  - budget 150: 6% / 129 changes, then 17%.
  - budget 300: 4% / 55, then 48%. Over 3600 ticks: 53% / 162.
  - budget 600: 3% / 21, then 30%. Over 3600 ticks: 52% / 88.
  - Choice: 600, which gives the same throughput with half the recipe changes.
- **Flicker.** No recipe was held for under 10 ticks in any run. A drop followed by a pick shows as
  2 changes, 1 tick apart.
- **Idle after demand.** After S1 + S2, a further 7200 ticks: F is empty and all 20 cells have no recipe.
  The chests are empty (hoard 0) because trash returned everything. Stock left over: servers 7 (B = 5),
  components 353, advanced circuits 100.
- **Ratio.** Over 3600 ticks: ≈10 cells on components, 3 on advanced circuits, 5 on servers. Components are
  the bottleneck (50 per server), so about 17 would be right. On an already-warm copy, a 3000-tick run
  reached 79% working with 15 cells on components.

## What failed and why

- **The budget burned during the recipe-switch dump.** A new recipe is applied only after the dump
  inventory is drained, which took 80–265 ticks here. "Recipe set and not working" was true for ST but
  not for the machine. Fix: BUDGET also requires `anything(AG) > 0`, i.e. the recipe really is set.
  This forced L to be counted negative (an offset of 720720) so it cannot fake an ingredient.
- **A leave re-picked the same item.** The index pipeline (LEAVES → MOD → SELF) is 3 ticks, but drop →
  take is 1 tick. Fix: count the leave 2 ticks before the drop (C = 2 − budget and not working).
- **The old HOLD value survived a recipe change** (over-requests). Fix: COUNTER also resets, and
  emits `signal-P`, while there is no recipe.
- **B = 1 stack** builds a whole stack after any request (+50 research servers). B = stack ÷ 10 is set
  by `A.BDIV`.
- **Space.** 15 combinators per cell do not fit the old 9-slot cell zones. The extras are placed by
  `A.pick`, which searches for free slots within wire reach.

## Open problems

- **Herding (the biggest weakness).** R hands each new item to exactly one helper (the preempt). Every
  other cell finds work only through blind re-picks after a full starvation budget. At a cold start,
  F = {server} for the first ticks, so 18 helpers pile onto the server, request its ingredients, starve,
  and leave together. The same happens whenever an item leaves F and frees its cells. Each wrong guess
  costs budget + dump + first delivery ≈ 900+ ticks. That is why S1 (600 ticks) scores below the
  baseline.
- **Cumulative budget.** Even well-placed helpers leave eventually after delivery hiccups, and each leave
  costs a dump.
- **Ingredient targeting (§4.4 C.3) not tried.** It needs AG ∩ F, but both are green nets. That means a
  colour swap plus about 2 combinators.
- The blueprint was checked structurally (counts and wires), not by pasting it into a game.
