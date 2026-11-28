# Mall benchmark: design

## Why

The scorecard rewards a busy mall, not a good one. "Working %" counts surplus cable as good, nothing
says what a run cost, and nothing gives the target, so 80% could be fine or terrible. The new
benchmark measures every run against a computed optimum, in time **and** energy, per cell, and shows
what each cell actually did.

## Goals

- **One fixed scenario: 50 `beacon`.** A recursive tree (AC, EC, steel, cable) that hits the known
  AC bottleneck.
- **Time:** ticks to 50 beacons, and ticks until all 20 cells are idle again.
- **Two optimums**, both computed at run time, never authored:
  - **Perfect mall:** total craft-seconds of the tree ÷ 20 cells. The fixed target.
  - **Realistic:** perfect + the one start-up nobody avoids (first robot delivery, measured).
    The gap between the two is what the engine itself costs.
- **Energy, robots first** (the user: most energy goes to robots), in MJ per beacon,
  split by consumer type: roboports (robot charging), assemblers, inserters, combinators.
- **Ideal energy:** each ingredient carried once. Waste = items carried beyond that: ingredients
  dumped on a switch and fetched again, and surplus product.
- **Per cell:** useful time, then the rest split into switching, starved, output full, no recipe,
  and surplus (crafting something the batch no longer needs).
- **What each cell is crafting:** a timeline of all 20 cells, recipe and state over time, so
  behaviour like synchronised AC ↔ cable flips is visible at a glance.
- **Comparable runs:** two run files side by side (e.g. r2-b vs r6).

## Non-goals

- Changing any mall design. This only measures.
- A live in-game display (headless servers have no screen).
- The full save. Sandbox only, as for rounds 4–6.

## Approaches

- A. Everything in `harness.lua`: one call, text report. A 20-cell timeline is unreadable as text.
- **B. Thin recorder in the game, analysis in Python. Picked by the user.** Facts are recorded once
  and the analysis reruns without the game.
- C. Live in-game overlay: impossible on the headless copies.

## How

**`bench/bench.lua`** — loaded after `harness.lua` (and the design under test). Records only facts:

- `BN.start(target, n, cap)` sets the demand via `H.demand`, unpauses, and runs until `n` made
  **and** all cells idle, or `cap` ticks (default 18000).
- **Static, at start:** each cell's `crafting_speed` and productivity bonus (modules and beacons
  included by the engine); the recipe tree of the target, walked down to items not on the mask
  (`H.set_mask`) — recipe, energy, ingredients, products; starting network stock of every tree item.
- **Events, on change only:** a cell's recipe; a cell's state (`entity.status`); each finished craft
  (`products_finished`) with its recipe.
- **Every 60 ticks:** cumulative `input_counts` from a mall pole's `electric_network_statistics`
  (per prototype → grouped by type in Python); robot counts in network 18; items in the cells'
  active provider chests (the dumps).
- **Robot traffic:** items delivered into the cells' requester chests (inflow), per item.
- Writes one JSON per run to `script-output/bench_<tag>.json` (`helpers.write_file(..., 0)`).

**`bench/analyze.py <run.json> [<other.json>]`** writes one self-contained HTML file:

- **Score row:** t(50), t(idle), perfect and realistic optimum, % of optimum; MJ total, MJ per
  beacon, ideal MJ, by consumer type.
- **Ideal time:** expand the tree for 50 beacons **net of starting stock**, with productivity;
  Σ crafts × energy ÷ speed, ÷ 20 cells. Realistic adds the fastest recipe-set-to-first-craft
  seen in the run.
- **Ideal energy:** measured robot MJ per item delivered × the minimum items the tree needs.
  Calibrating per item from the run itself avoids modelling distance and robot speed.
- **Surplus:** crafts of a recipe after its net requirement was met, attributed to the cell that
  made them.
- **Timeline:** one lane per cell (C1–C20 in chain order), colour = recipe, shade/hatch = state,
  marks for switches; a 60-tick energy strip underneath. Two runs stack vertically on one time axis.
- **Per-cell table:** the time buckets above, crafts per recipe.

## Builder's calls

- Python is stdlib only; the HTML embeds its own SVG (no CDN). Use the `dataviz` skill for the chart.
- Exact state mapping from `defines.entity_status` to the five buckets; "switching" = recipe change
  until first craft of the new recipe, overriding the state underneath.
- How robot inflow is counted (chest diff per 60 ticks plus crafts consumed is fine).
- A `bench/README.md` with the run commands, and a line in the mall `README.md` Tools section.

## Constraints

- Sandbox save, fresh copy per run, own slot; build while paused.
- Never pipe `instance.ps1`; `H.run` and `BN.start` must not both own `on_nth_tick(1)`.
- Comments in `harness.lua`-style files: whole-line only (the RCON client flattens blocks).
