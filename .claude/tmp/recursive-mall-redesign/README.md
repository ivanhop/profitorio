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
- `am2-recipe-mask.txt`: a blueprint with one constant combinator holding every recipe an
  assembling machine 2 can craft on nauvis without a fluid ingredient or product, as recipe
  signals = 1 (392 recipes; `.json` lists them).
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
