# Round 3, r3-grace (grace until first craft)

`build.lua` = r2-b plus `MB.GRACE` (default 900; `MB.GRACE = 0` builds exactly r2-b). `blueprint.txt` is
the grace-on mall block, exported from the fresh copy after the 3600-tick run.

## Delta (2 deciders per cell, in the cell's two unused slots f[7]/f[8])

- **GS (grace set):** reads XF red (X's output). When `X < 0` (the switch tick) it outputs `signal-B = GRACE`
  onto the A net. Then K counts down from 900 instead of 0. The R pulse of the first finished craft makes K
  drop its output for a tick, as in r2-b, so B goes back to 0 and the budget starts. Without a craft the cell
  reaches 0 after 900 idle ticks and walks down 120 ticks later.
- **GB (grace block):** `B (A net) > 1 AND H (A1 output, red) > 0` adds `signal-H = 1e7` to the P net.
  A working cell sits at B = 1, which is why the test is `> 1`. With the block on, the incumbent threshold
  beats every Q0 value (max about 3e6), so the cell cannot be moved by a T boost or by the
  unstaffed-item bonus. **That bypass existed in r2-b:** a shared holder has H = 999999, and an unstaffed
  F item's Q0 is at least 1.5e6, so X fired with no budget check at all.
  When the item leaves the list, H = 0 and GB is off, so the cell is freed at once.
  Sole holder: 2e9 + 1e7 still fits in int32.
- Observed in-engine: C2 at B = 404 with H on P = 10999999, while cells that were out of grace showed 999999.
- Count: **9 per cell + 15 head = 195** (r2-b: 155).
- Deviation from the spec: grace drains only on idle ticks, because K holds while the cell works. A cell
  that works for a while and then starves before finishing a craft gets more than 900 wall-clock ticks.

## Scorecard (grace on, each run on its own fresh copy)

| Run | Working | Recipe set, not working | No recipe | Changes | Hoard |
|---|---|---|---|---|---|
| S1 600 | 23% | 62% | 14% | 24 | 687 |
| 3600, demand on | **42%** | 39% | 19% | **142** | 420 |

- Time to 10 servers: **NOT reached** (5 made). First server at **784 ticks**.
- 3600-tick split (average cells): components 8.21 / AC 3.06 / server 3.36 / blank tech card 1.39 /
  steel beam 0.19. Crafts: 73 components, 2 AC, 5 servers.
- **Grace off was not measured this round.** The fresh-copy restart hung my script, because `tail` waited
  on the server's inherited stdout. That cost the time slot. Reference: r2-b on its own copy measured
  S1 9% with 58 changes, and the 3600-tick run 82% with 21 changes and 10 servers (r2-b notes, older
  unpaused harness, so not strictly comparable). r3-reference should have the comparable r2-b numbers.

## Verdict and open problems

- On S1, grace looks good: 23% against 9%, and 24 changes against 58. It does what it should at
  switch-in.
- Over 3600 ticks, grace looks clearly worse: 42% with 142 changes, against 82% with 21. Likely cause:
  blocking the unstaffed-item jump strands 3 to 4 cells on the server and AC. They start on items whose
  inputs never come. After 900 + 120 idle ticks they all walk down at about the same time, and they
  herd. Each walk-down starts a new 900-tick grace, so a starving cell now takes about 1000 ticks per
  hop instead of 120.
- Next: cap the grace on starvation, e.g. GRACE 300 to 450 (about the first-delivery time), or end
  grace when ingredients are present but the cell is not working. Then rerun on and off on the same
  harness.

## Blueprint v2 (2026-11-28): use `blueprint-v2.txt`, not `blueprint.txt`

`blueprint.txt` is broken in two ways:
- **Its export area started at y = 102**, so it cut off the head's top row at y = 100.5. It holds
  191 combinators, but the build makes 195 (197 with the constant combinators).
- **It contains the relay pole at (−220.5, 103.5) that r2-b adds for the O bus.** That tile is
  inside the roboport at (−219, 105). `create_entity` placed it anyway, but a paste cannot. The two
  O-bus combinators are then 9.92 tiles apart with nothing between them. Every r2-b-based
  blueprint (r2-b, r4-*, r5, r6) has this flaw.

`blueprint-v2.txt` is exported from a fresh build over x −246..−213, y 98..139. Changes:
- the relay's two circuit wires now run through the existing pole at (−221.5, 103.5), which had
  no circuit wires;
- the 11 beacons (the save's planned beacon column, ghosts in the save) and the rig assembler at
  (−217.5, 139.5) are left out.

It has 495 entities, 197 combinators and 716 wires, with no circuit wire over 9.75 tiles.

**Paste test, on a fresh sandbox copy:**
1. Removed the 186 old combinators.
2. `build_blueprint` placed the blueprint in place at (−230, 119); all 200 ghosts revived.
3. Re-exported the result: no entity or setting differences, and the same 173 circuit networks as
   the scripted build.
4. Beacon benchmark: 50 delivered at 24 117 t (52% of perfect), idle at 27 401. The scripted build
   gave 22 137 t (57%) on its own copy. Run data: `bench/results/bench_r3-grace-pasted.json`.

**To paste in a game:** deconstruct the mall's old combinators first, because a paste does not
remove them. Then paste so the cells line up. The blueprint holds the 20 cells' assemblers, chests,
inserters, poles and roboports at their existing positions.
