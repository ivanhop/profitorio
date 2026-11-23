# Recursive mall redesign: working folder

**Start at `PROGRESS.md`**: the handoff, decisions and next steps. This file holds the tools and the full round results.

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

## Session 2, round 3: results (details in `round3.md` and `r3-*/notes.md`)

Comparable numbers: all with the paused harness and the 367 mask, each on a fresh copy.

| | S1 working / changes | 3600 t working / changes | Servers in 3600 t (first at) | Idle after demand cleared? | Combinators |
|---|---|---|---|---|---|
| Baseline 0.2.7 | 10% / 68 | 10% / 135 | 1 (79, from preloaded ingredients) | — | 199 |
| r2-b (reference) | 11% / 57 | 70% / 108 | 8 (1529) | **No** | 155 |
| design C + mask (reference) | 35% / 27 | 68% / 42 | 6 (1240) | **No** | 92 |
| r3-grace (on) | 23% / 24 | 42% / 142 | 5 (784) | not run | 195 |
| r3-second (on) | 13% / 61 | not measured | — | not run | 177 |

- **Biggest finding: no design ends a batch idle.** After the trigger is cleared, all cells pick
  recipes up again. Server stock bounces (12 → 1 → 10), and C's AC stock climbs from 54 to 126.
  - Main suspect, untested: the cells' own circuit-set requester chests sit on network 18, so they
    appear in the head's missing-requests count. That is the bug #2 mechanism: the mall feeds itself.
  - **Fix this before tuning anything else**: it violates the goal outright.
- **Advanced circuits limit both designs.** r2-b made 0 AC in 3600 t, even with 0.8 cells on it;
  C made 37.
- **Grace (900 cap) helps the start and hurts the long run.**
  - Stranded cells sit out 900 + 120 ticks on items whose inputs never come, then walk down together.
  - Each hop restarts the grace.
  - It also found that r2-b lets a shared cell jump to an unstaffed item with no budget check.
  - Next to try: a cap of 300–450, or ending grace once the cell is starved.
- **Second cell:** built (DIFF bus = 1001 × working − 1000 × cells, so it is > 0 only when every cell
  on the item works), but not measured. Warning sign: in S1, AC held about 3 cells, all starving.
- **Tooling failures this round (both agents lost their on/off comparison):**
  - Never pipe `instance.ps1` into `tail`/`head`. The server inherits the pipe and the reader waits
    forever. Call it bare.
  - `instance.ps1 -Stop` now waits for the process to exit. Before that, a quick restart could reach
    the old server: one "fresh" copy already had `H` defined.
  - For an on/off pair, start two servers in parallel (two slots) rather than one after the other.
  - Runs shorter than 600 ticks vary 9–42% between copies. Judge features on 3600-tick pairs.

## Session 2, after round 3: the "never idle" diagnosis (r2-b, measured)

**Not a bug: the batch was simply longer than the test.** My self-feeding suspicion was wrong.

- **No demand from the start:** all 20 cells stay without a recipe for 1800 ticks. Nothing leaks
  onto the list.
- **After a 2400-tick 50-server batch, demand cleared:**
  - The list held server (D+B = 9, stock 3 < B = 12), AC (missing 8 from the server cell's chests,
    stock 0 < B = 50) and components (stock 0 < 50).
  - The hysteresis is refilling every intermediate's buffer, as designed. The trigger chest keeps
    the 50 servers it received, so the network stock really is 3.
- **It goes fully idle about 3600 ticks after demand is cleared:** 20/20 no recipe, hoard 0, stock
  server 13 / AC 69 / components 707.
- **Why it takes so long:** a server needs 50 + 5×2 = 60 components, and ~17 component cells make
  ~90 per 1200 ticks, so a 50-server batch is about 3000 components. Rounds 1–3's "not idle at
  3600" verdicts all ran out of time.
  - **Use a small batch for batch-and-idle tests**, e.g. 5 servers or 20 power switches.
- **The real defect found: AC ↔ cable oscillation while winding down.** 181 changes in 2400 ticks,
  41 of them within 60 ticks of the same cell's previous change.
  - Top transitions: `- → AC` 42, `cable → -` 41, `AC → cable` 40.
  - The cycle:
    1. AC cells starve on cable and walk down to cable.
    2. Many cable cells fill cable's small buffer (stack ÷ 4 = 50 = 12 AC crafts) in moments.
    3. Cable leaves the list and frees them all at once.
    4. They re-pick AC and drain the cable, and the cycle repeats. Every hop costs a dump.
  - Candidate fixes:
    - a larger buffer for cheap fast intermediates (stack ÷ 4 penalises 200-stacks consumed 4 at a time);
    - freed cells spreading out instead of all re-picking the top item;
    - a short hold after an item-left-list release.
