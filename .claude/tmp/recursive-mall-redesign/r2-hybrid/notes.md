# Round 2: hybrid (C dispatcher + B walk-down)

`build.lua` = design C's build plus one hybrid block at the end. Load `harness.lua`, then `mask.lua`,
then send `build.lua`; then `H.rig_off()`. Idempotent on a fresh colin0.2.7 copy. `blueprint.txt` is
`H.export` of the mall area (rig assembler not stripped).

## Delta from C

- **Per-cell reporter C4** (decider): `each(green: read ingredients) > 0 AND W = 0` → `each = 2^20`,
  output onto C2's red output, i.e. the existing V bus. No new bus wire. V[item] is now
  `cells + 1024·starving + 2^20·(starving cells that need it)`.
- **Head +3**: `Sdec2 = (V>>10) AND 1023` restores the starvation accumulator's input;
  `Shdec = V >> 20` gives short counts; `ShF` = `short > 0 AND eligible (Elig out) > 0` → `each = 2^24`,
  added to the selector input. So an eligible, listed ingredient that a starving cell is waiting for
  beats every D'Hondt score, and the rebalancer (which compares against the selected max) preempts
  for it. Filtering by Elig keeps plates and other unlisted ingredients out.
- **Mask**: `H.set_mask(mask)` (367 items incl. `kr-steel-beam`).
- **B = stack ÷ 4**: arith `Q4` (/4) inserted after the stack-size selector `L3`.
- All wires ≤ 9.75 (asserted in `B.wire`).
- **Combinators: 112 + 2 constants** (C: 92). 4 per cell on 16 cells; **C10–C13 have no reporter**:
  no free tile next to them (C's head occupies their slots). They still run C's normal logic.

## Scorecards (fresh copy, slot 4)

| Run | working | recipe, not working | no recipe | changes | hoard |
| --- | --- | --- | --- | --- | --- |
| S1 `H.run(600,"s1")` | 30% | 51% | 19% | 26 | 568 |
| Long `H.run(3600,"long")`, demand on, directly after S1 | 76% | 15% | 9% | 17 | 827 |
| (C round 1 for reference: S1 35±4, long 78% / 26 changes) | | | | | |

Long-run split (avg cells): components 14.66, AC 1.87, server 1.19, blank tech card 0.51,
copper cable 0. Crafts: components 192, AC 24, server 11, tech card 12.
S1 split: components 12.5, AC 1.3, server 1.2, tech card 1.1, cable 0.12.

## Weakness / findings

- **No measurable gain over C.** S1 30% is inside C's ±4 band; long run 76% vs 78% with fewer
  changes (17 vs 26). One run each, no repeats (time limit).
- **Cable still gets no cells.** In S1 C15 took copper-cable at t=261 (that is the walk-down
  firing) and lost it at t=334; in the long run cable never held a cell. Likely the starvation
  backstop and the rebalancer both need A ≥ 2, so a single cable cell cannot be their victim; the
  likelier cause is that cable left the list (its small batch was filled, latch dropped, M cleared).
  If so, cable was not actually short in this scenario and the walk-down had little to fix. Not
  traced.
- Components hog 14.7 cells; C19/C20 sat ~50% starved and C10 (no reporter) starved all 3600 ticks
  on components, which suggests components are over-assigned relative to their inputs.
- Spot-check at the end of the long run: Shdec output was empty (no reporting cell starving at that
  instant), so the bonus is idle in steady state, as intended.

## Open problems

- Exempt walk-down recipients from being rebalance victims (e.g. add the 2^24 bonus to VF's
  victim score too), so a cable cell given for a shortage is not taken back.
- Find tiles for C10–C13 reporters (relocate part of the head to x -230/-229, which is free 124..138).
- Repeat S1/long to get variance; test the lamp/cable T3 scenario, where cable starvation is real.
