# Recursive mall redesign: progress and handoff (start here)

Last session: 2026-11-28 (session 3). Unrelated to Profitorio: this is the circuit-controlled mall in
the user's Space Age + Krastorio2 save `colin0.2.7`. The real save is never touched; everything runs
on isolated headless copies.

## Documents

| File | What's in it |
|---|---|
| `PROGRESS.md` (this file) | Where things stand, decisions, what to do next, lessons |
| `README.md` | The goal, how to use the tools, the standard scenario, and every round's results in full |
| `research.md` | Session 1: the 0.2.7 wiring (§1), its bugs (§2), engine facts (§3), the original design (§4), save setup (§0) |
| `round3.md` | Round-3 plan, the scorecard definition, priority rules |
| `design-a/`, `design-b/`, `design-c/` | Round 1: three rival designs (`build.lua`, `blueprint.txt`, `notes.md`) |
| `r2-b/` | **Current best design (hardened B).** Base for all further work |
| `r2-hybrid/`, `r2-switch/` | Round 2: the C + walk-down hybrid (no gain); the recipe-switch cost investigation |
| `r3-grace/`, `r3-second/`, `r3-reference/` | Round 3: grace (worse), second cell (unmeasured), reference numbers for r2-b and C |
| `instance.ps1` | Start or stop an isolated server copy: `-Dir <new dir> -Slot N`, RCON 2712N |
| `harness.lua` | Scoring tools (`H.*`). Loading pauses the game; `H.run` unpauses it |
| `mask.lua` | `H.set_mask(e)` loads the 367-item AM2 mask (`am2-item-mask.json`/`.txt`, includes `kr-steel-beam`) |
| `layout-0.2.7.json` | Blueprint JSON of the original mall block: every entity, setting and wire |

Repo docs that matter here:
- `tools/check/probe_client.py` is the RCON client.
- `factorio-docs/markdown/` is the 2.1 API (grep it, don't load it). Recipe selection:
  `factorio-docs/markdown/auxiliary/circuit-recipe-selection.md`.
- Memory notes on parallel instances, Git Bash mangling `/args`, PowerShell gotchas and short tests
  are loaded automatically.

## Goal (unchanged)

- Demand on logistic network 18 builds the item and every intermediate.
- All 20 cells busy while there is demand, all idle when there is none.
- No flicker.
- Cells split between items in the needed ratio, with no recipe table.
- A small buffer at the end of a batch, and no hoarding.
- Keep the existing assemblers, chests and inserters.
- Deliver as a blueprint.

## Where things stand

Comparable numbers: paused harness, 367 mask, fresh copies. Full tables in `README.md`.

| | S1 working / changes (600 t) | 3600 t working / changes | Servers in 3600 t | Combinators |
|---|---|---|---|---|
| Original 0.2.7 | 10% / 68 | 10% / 135 | 1 | 199 |
| **r2-b (hardened B)** | 11% / 57 | **70% / 108** | **8** | 155 |
| design C + mask | 35% / 27 | 68% / 42 | 6 | 92 |

**r2-b in brief:**
- A head list with hysteresis.
- Global buses, with a clock that lets one cell decide per slot.
- Helpers that starve walk down to their own short ingredient (the walk-down; 1 decider condition).
- The budget resets on every finished craft (`signal-R`).
- Buffer = stack ÷ 4.
- 7 combinators per cell + 15 at the head.

**"Never idle" was a false alarm.** r2-b goes fully idle about 3600 ticks after demand is cleared,
once the intermediate buffers are refilled. A 50-server batch is about 3000 electronic components,
which is longer than every earlier test. Use small batches for idle tests.

**The defect to fix: AC ↔ cable oscillation.** In the wind-down there were 181 changes in 2400
ticks, 41 of them within 60 ticks.
- AC cells starve on cable and walk down to it.
- Cable's small buffer (50) fills almost at once, and cable leaves the list.
- All its cells are freed together, re-pick AC and drain the cable again.
- Every hop costs a switch of about 450 ticks.

## Decisions made by the user

- **Fast inserters stay.** No bulk-inserter swap.
- **No chest requests driven by the commanded recipe.** No combinator maps a recipe to its
  ingredients. A probe assembler per cell would be needed, for about 6% gain.
- **No buffer cap.** "What is to say that 2 stacks is enough."
- **Adopted for round 4: the adaptive buffer** (the user's design):
  - **Early start:** an item starts production when stock drops below 50% of its buffer B, and stops
    at 100%.
  - **Grow on stockout:** when stock hits 0% while there is demand (D = missing − stock > 0), B grows
    by one step (a quarter stack), once per stockout event, not per tick. B may start at 0.
  - **Limits itself:** B only grows while the early start fails, so it stops growing once it is big
    enough. It also covers player requests: anything requested while out of stock gets buffered for
    next time.
  - **Known risk:** under permanent overload (demand > capacity) B grows every cycle, and it never
    shrinks afterwards. Measure first; a slow decay could be added later.
  - **Circuit sketch, all at the head (~5–6 combinators):**
    - a B memory per item;
    - one arithmetic for B/2;
    - the existing latch fed with D + B/2, plus its own B/2 output while on, gives "on at 50%, off
      at 100%";
    - a stockout edge (D > 0 now and not last tick) × step, added to B.
    - Raw D needs its own wire, separate from the latch feedback.

## Session 3 (2026-11-28): sandbox save, rounds 4–6

**Tooling:**
- `harness.lua` sets `game.speed = 1000` on load and re-pauses when `H.run` ends. It used to keep
  running past the window.
- `mall-sandbox.zip` is the mall trimmed out of colin0.2.7: same coordinates, infinite power,
  over-provisioned finite stock. It runs at ~1100 UPS against ~870 for the full save, because most
  of each tick is mod Lua. It scores in the same range. See README §Sandbox save; rebuild it with
  `sandbox-build.lua`.
- All numbers below are on the sandbox, on/off pairs run in parallel on fresh copies.
- r2-b's off runs vary 79–86% working and 52–60 changes between copies.

| Round | Feature | 50 servers / 3600 t (on vs off) | 5-server batch to idle (on vs off) | Verdict |
|---|---|---|---|---|
| 4 | Hold 450 t after release (`r4-hold/`, +40 comb.) | 80% vs 86%, 61 vs 52 changes | 10800 vs 8400 t | **Rejected** |
| 4 | Adaptive B, edge on D > 0 (`r4-adaptive/`) | 75% vs 79% | never idle; B(server) = 36 | Runaway |
| 5 | Adaptive B, edge on stock ≤ 0 ∧ D > 0 (`r5-adaptive/`) | 82% vs 81% | never idle; AC still growing | Runaway: re-fires per item passing through |
| 6 | **Adaptive B + re-arm latch** (`r6-adaptive/`, 162 comb.) | 77% vs 80%, 82 vs 60 changes, 9 vs 8 servers, first at 1046 vs 1381 | 8400 vs 8400 t, 16 vs 23 fast changes, hoard 0 | **Meets the spec**; small gain |

- **r6:** after B grows, the stockout trigger stays disarmed until stock is back above B/2. That
  gives one step per drain-and-refill. B settles at server 12, AC 50, components 100, cable 150,
  and stops growing.
- **The cable ↔ AC oscillation is weak on the sandbox:** about 16–23 fast changes per batch. So
  neither feature has much to fix here. On the full save the base also tops up stock while a run
  goes on.

## Benchmark: 50 beacons (`bench/`, session 3)

Runs, report and how to read them: `bench/README.md`, `bench/results/` (open `report.html`).
Sandbox, fresh copy per design, ghosts removed, 54000-tick (15 min) cap, **one run each**.
Perfect = 12 500 t (208 s) for every design.

| Design | 50 delivered at (% of perfect) | All idle at | Useful / switching / surplus / none | Recipe changes (reached a craft) | Total MJ | MJ per beacon | Robot items × ideal |
|---|---|---|---|---|---|---|---|
| **r3-grace** | **22 137 (57%)** | 25 591 | 49 / 16 / 20 / 11% | 350 (111) | 6 246 | 110 | 1.7 |
| design-a | 26 382 (48%) | 27 818 | 45 / 27 / 8 / 18% | 926 (131) | 6 021 | 112 | 2.0 |
| design-c | 39 917 (31%) | — | 23 / 8 / 17 / 48% | 396 (157) | 8 216 | 123 | 2.1 |
| r3-second | 47 144 (27%) | 52 578 | 24 / 35 / 14 / 26% | 3 777 (335) | 20 312 | 363 | 4.6 |
| r4-adaptive | 47 370 (27%) | — | 23 / 32 / 30 / 12% | 2 649 (605) | 20 178 | 348 | 3.6 |
| r4-hold | 49 047 (26%) | — | 23 / 36 / 18 / 21% | 2 827 (754) | 20 881 | 360 | 4.1 |
| r2-hybrid | 50 065 (25%) | — | 23 / 16 / 4 / 55% | 504 (140) | 6 915 | 126 | 1.5 |
| r6-adaptive | 30 of 50 | — | 22 / 41 / 15 / 22% | 3 587 (714) | 20 690 | 690 | 4.1 |
| design-b | 28 of 50 | — | 21 / 45 / 2 / 31% | 4 956 (613) | 22 285 | 796 | 4.9 |
| r2-b | 27 of 50 | — | 21 / 44 / 3 / 30% | 4 775 (629) | 22 116 | 819 | 4.9 |
| baseline 0.2.7 | 26 of 50 | — | 15 / 1 / 0 / 81% | 3 496 (68) | 6 156 | 237 | 0.9 |
| r5-adaptive | 25 of 50 | — | 21 / 41 / 16 / 20% | 3 288 (734) | 21 184 | 847 | 3.9 |

- **Two families.** Designs that hold a recipe (r3-grace, A, C, hybrid: 350–930 changes) use
  6–8 GJ and 110–126 MJ per beacon. The r2-b family without grace (2 600–5 000 changes) uses
  20–22 GJ, 3–8× more per beacon, and 4 of its 7 don't finish in 15 minutes.
- **r3-grace is best on every axis**: first to 50, first idle, least energy. Round 3 rejected it on
  the 3600-tick server test; the longer batch reverses that verdict.
- **Robots are 72–92% of all energy.** Churn is what costs: each abandoned switch dumps the cell
  and the robots carry it twice. The baseline uses little energy only because 81% of its cells sit
  without a recipe.
- **Caveats:** one run per design, and copies vary (r6 made 45 in an earlier run with ghosts, 30
  here). Repeat the top designs before deciding. Design A ran from `results/design-a-ascii.lua`:
  its `≥`/`≠` comparators are rejected by 2.1.24, so they were swapped for `>=`/`!=`.
- **Blueprints:** use `r3-grace/blueprint-v2.txt`. It was tested by pasting it into a fresh copy
  and benchmarking it: delivered at 24 117 t, 52% of perfect.
  - **Every older r2-b-based `blueprint.txt` is broken.** r2-b's O-bus relay pole at
    (−220.5, 103.5) sits inside a roboport, and r3-grace's export also cut off the head row at
    y = 100.5. Details: `r3-grace/notes.md`.
- `results/with-ghosts/`: the first r6 and r2-b runs, skewed because robots built the save's 11
  beacon ghosts from the batch. Kept as evidence only.

## Next (user to decide)

- **Adopt r6 as the new base, or keep r2-b?** r6 is the user's design, working as specified. Its
  gain is within copy-to-copy noise, except a sooner first server.
- **Knobs that would change the user's design:**
  - a bigger growth step than a quarter stack;
  - growing intermediates only;
  - slow decay.
- **Tests:** run r6 on the full save, where the oscillation was first seen, and with longer runs or
  repeats to get past the noise.

**Format the user wants:** 15-minute agents, a progress request every 5 minutes, and agents reply
via SendMessage.

**Also open:**
- Grace with a shorter cap (300–450) or ending once the cell is starved (the 900 version hurt).
- A long run for the second-cell rule.
- The C10–C13 reporter tiles in the hybrid.
- Whether combinator memories survive save and load.
- Pasting the final blueprint into a real game.

## Lessons from this session

**Engine and game facts (measured):**
- **A recipe switch costs about 450 ticks, up to about 800:**
  - the current craft finishes (≤30);
  - the input inventory is dumped at 12 t/item through the fast output inserter (41 items = 500 t),
    even when the new recipe shares an ingredient;
  - a 270–320 t robot leg, which is distance: the warehouse at (−208,135) is 33 tiles away and
    robots are idle;
  - the chest requests only start after the dump.
- **A starvation budget shorter than about 450 ticks churns** unless something else gates the move.
  A: budget 150 gave 129 changes and 600 gave 21. C's per-cell budget of 300 churned. B survives
  only because walk-down needs a network-wide shortage.
- **Advanced circuits are the batch bottleneck.** Each server also needs 50 components.
- Signals:
  - `get_item_count` on a network is net of robot reservations, so it can be negative.
  - A newly set constant combinator shows on the wire one tick later.
  - Wires longer than about 9.75 tiles are dropped when a blueprint is pasted, even though the API
    accepts 14.
- On a headless server:
  - `helpers.write_file(name, data, false, 0)` is the only form that writes.
  - `game.tick_paused` works.
- The mask: `landfill`, `electric-engine-unit` and `maraxsis-fish-food` are left out, because their
  item signals pick an unusable recipe.

**Running parallel agents:**
- **Isolation:**
  - Give each agent a private scratch folder and its own slot, with the port hardcoded.
  - In round 1 a shared `rc.sh` sent agent A's builds to another agent's server.
- **Restarts:**
  - Never pipe `instance.ps1` into `tail`/`head`. The server inherits the pipe and the reader hangs
    forever, which cost both round-3 feature agents their comparison.
  - `instance.ps1 -Stop` now waits for the exit, because a quick restart could reach the old process.
- **Measuring:**
  - Run on/off pairs on two parallel servers, not one after the other.
  - Judge features on 3600-tick runs; 600-tick S1 varies 9–42% between copies.
  - Build while paused, so robots and stock don't drift for however long the build takes.
- **Checking agents:**
  - Agents can claim "wiring only" for something they simulated by script. The user caught one.
    Require real combinators, or an explicit "simulated" label.
  - Agents compare against stale numbers from other setups. Give them the comparable reference
    numbers in the brief.
  - Each design picks its own buffer unless told. Fix shared parameters in the brief.
