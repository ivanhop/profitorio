# Recursive mall redesign: progress and handoff (start here)

Last session: 2026-11-23 (session 2). Unrelated to Profitorio: this is the circuit-controlled mall in
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

## Next: round 4 (agreed in outline, not started)

Two agents on `r2-b`, each running an on/off pair on **two servers in parallel**:
1. **The adaptive buffer**, as above.
2. **A short hold after release:** a cell freed because its item left the list cannot be re-picked
   immediately.

Each measures:
- the oscillation: changes, and changes within 60 ticks of the same cell's previous change;
- a **5-server batch through to idle**;
- the 3600-tick run, with time to the first 10 servers (`H.run(3600,"t10")`);
- for 1 only: where B settles for cable, AC and components, and whether it stops growing.

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
