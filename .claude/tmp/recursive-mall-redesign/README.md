# Recursive mall redesign: working folder

Unrelated to Profitorio. Background, engine facts and the first design: `research.md`.

## Goal (what any design must meet)

- Demand on logistic network 18 makes the 20 cells build the item **and every intermediate**, recursively.
- Every cell busy while there is demand; all idle when there is none.
- No recipe flicker, and no latching that reacts to robot-reservation noise.
- Cells split between an item and its ingredients roughly in the needed ratio, adapting to modules
  and beacons without a per-recipe table.
- Batches end with a small buffer, and chests don't hoard.
- Keeps the existing assemblers, chests and inserters; delivered as a blueprint.

## Tools

- `instance.ps1 -Dir <new dir> -Slot N` copies colin0.2.7 and starts an isolated headless 2.1.24
  server with RCON on `127.0.0.1:2712N` (password `probe`), game port `3429N`. `-Stop` stops it.
  Use a different slot per concurrent server.
- `harness.lua` — load it once per server start, from the repo root:
  `python tools/check/probe_client.py --host 127.0.0.1 --port 2712N --password probe < .claude/tmp/recursive-mall-redesign/harness.lua`.
  Then send `/silent-command` lines from a file (never as a Git Bash argument):
  - `H.rig_off()` stops the test rig chest feeding the list (bug #2). Do this first.
  - `H.demand(item, n)` / `H.demand()` sets or clears the trigger requester at (−207.5,122.5).
    The save already requests 50 `kr-research-server`.
  - `rcon.print(H.run(ticks, tag))`, wait, then `rcon.print(H.report())` gives the scorecard
    (working %, recipe-but-not-working %, no-recipe %, recipe changes, chest hoard, per-recipe cells
    and crafts). The change log goes to `<dir>/script-output/<tag>_changes.txt`.
  - `H.export(name)` writes a blueprint of the mall block to `script-output/<name>.txt/.json`.
  - `H.cells()` gives C1..C20 in chain order.
- `am2-item-mask.txt`: the head's mask as a blueprint, one constant combinator with **item**
  signals = 1 (367 items; `.json` lists them). The items made by every recipe an assembling
  machine 2 can craft on nauvis with no fluid in or out, minus the "environment" tab (rocks).
  One section per inventory tab, each subgroup on a new row of 10. Item, not recipe, signals:
  each × each only pairs identical signals, and the roboports report items.
  - Dropped because an AM2 given that item signal picks an unusable recipe (measured with every
    recipe researched): `landfill` and `electric-engine-unit` select the water/lubricant recipe,
    and `maraxsis-fish-food` selects nothing (its only recipe eats fish food).
  - Measured in 0.2.8: request 97 servers → list holds the server and its five ingredients, and
    C1–C6 take them.
- Mall layout dump (blueprint JSON of x −245..−214, y 100..152, all settings and wires):
  `layout-0.2.7.json`.

## Standard scenario

On a fresh copy: load the harness, `H.rig_off()`, build the design, then run:

- **S1 demand** `H.run(600,"s1")`: 50 servers requested, with stock at 0.
- **S2 off**: `H.demand()`, then `H.run(600,"s2")`.
- Longer runs (e.g. 3600 ticks for convergence) only when a question needs one.

## Baseline (0.2.7, as found, rig off), S1

Working 10%, recipe set but not working 6%, no recipe 84%, 68 recipe changes in 600 ticks, chest
hoard 4627 items.

- C1 kr-research-server: starved the whole time.
- C2 advanced-circuit and C3 kr-electronic-components: working.
- C4–C20 idle, each with 4 one-tick ripples (bug #4). C4 also flips to copper-cable.

## Lessons from running agents in parallel

- **Give each agent its own private scratch folder for helper scripts.** In session 2 the designers
  shared one scratchpad. One rewrote a shared `rc.sh` to its own port, and agent A's build commands
  then went to another agent's server. Hardcode the port inside a private file. Never use shared
  names such as `rc.sh` or `q.lua`.
- `helpers.write_file` writes nothing on a headless server unless given player index 0:
  `helpers.write_file(name, data, false, 0)`. The harness now does this.

## Session 2 result: three designs compared

| | A (research.md §4) | B (walk-down helpers) | C (central dispatcher) |
|---|---|---|---|
| S1 working (600 ticks) | 4% | 24–28% | 35% (±4) |
| Long demand-on run | 52% at 3600 | 48→99→100% over 3×1200, 0 changes | 78% at 3600, 26 changes |
| Split comp/AC/server | ~10/3/5 | 18/1/1 | 12.8/5.2/1.2 |
| Combinators | 15/cell + 11 head = 311 | 7/cell + 15 head = 155 | 3/cell + 32 head = 92 |
| Buffer B | stack ÷ 10 | stack ÷ 4 | 1 stack |
| Blueprint pasted back in a game? | decoded only | imports cleanly | yes, rebuilt and ran |

- **S1 is limited by the engine** in every design: the first robot delivery takes 180–700 ticks, and
  every recipe change leaves the machine with no recipe for 100–360 ticks until its single output
  inserter has emptied the old ingredients.
- **A herds.** R hands each new item to one helper, the rest re-pick blindly, and each wrong guess
  costs a budget plus a dump plus a robot delivery.
- **B converges best.** The walk-down costs one decider condition per cell. Its blind variant (A's
  rule) reached only 56% at 3600 ticks.
- **C is smallest.** Its recipe is a 20-bit cell mask per item, ANDed per cell, so exactly one
  recipe signal and signal order never matters. Its split follows the shortage number, not the real
  bottleneck: cheap fast ingredients such as cable get too few cells.
- **Each design picked its own buffer**, so the S2 numbers can't be compared. Fix B before the next
  comparison.
- **Known for all designs:** steel beams and several Krastorio parts are not on the mask. Wires
  longer than about 9.75 tiles are dropped when a blueprint is pasted.

## Session 2, round 2 (15-minute agents): results

- **Comparability fix:** loading `harness.lua` now pauses the game (`game.tick_paused`), and
  `H.run` unpauses it. Round-1 and round-2 S1 numbers varied because the server kept running while
  an agent built, so robots and stock drifted for however long the build took. Build while paused.
- **r2-b (B hardened, 155 combinators): best so far.**
  - With the 367 mask, servers actually get built.
  - Over 3600 ticks: 82% working, 21 changes, split components 17.4 / AC 1.0 / server 1.0 / tech card 0.35.
  - **Budget reset on each finished craft** (signal-R): a clear win, 46% → 63% working and 77 → 13 changes.
  - **Raw-input fallback:** harmful (cells pile onto the top item), off by default.
  - **Weakness:** a slow item with an owner never gets a second cell. AC and the server are the batch
    bottleneck (about 7 servers per 1800 ticks), so S2 does not finish within a test.
- **r2-hybrid (C + walk-down, 112 combinators): no gain over C.** S1 30%, long run 76%. The
  rebalancer took the walk-down's cable cell back. C10–C13 have no reporter.
- **r2-switch (investigation):** a switch costs about 450 ticks, up to about 800.
  - Steps: finish the craft (≤30) + dump at 12 t/item through the fast inserter + robot leg 270–320.
  - The robot leg is distance: the warehouse at (−208,135) is 33 tiles away and robots are idle.
  - Remedies, cheapest first:
    1. drive the chest requests from the *commanded* recipe (first craft at about 310 instead of 450).
       **Not wiring only, despite the agent's claim** (user caught it): it was simulated by script.
       No combinator turns a recipe or item signal into its ingredients; only a machine's
       read-ingredients does, and that follows the live recipe. It needs an extra empty "probe"
       assembler per cell, or an authored lookup table (rejected in research.md §4.4 B). Unmeasured;
    2. bulk output inserters (12 → 5 t/item);
    3. prefer a recipe whose ingredients the cell's chests already hold (about 140).
  - Hold each assignment at least 1800 ticks.
