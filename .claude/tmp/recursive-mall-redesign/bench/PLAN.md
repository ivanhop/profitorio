# Mall benchmark: implementation plan

> Executed natively in this session (the user said "start"). Spec: `DESIGN.md`.

**Goal:** a recorder (`bench.lua`) and an analyser (`analyze.py`) that score a mall run on 50 beacons
against a computed optimum, in time and energy, per cell, with a timeline.

**Architecture:** the game records facts into one JSON file; Python derives every number and draws
the HTML. No number is computed in both places.

**Tech:** Factorio 2.1.24 Lua via RCON (`tools/check/probe_client.py`), Python 3.14 stdlib only.

## Global constraints

- Sandbox save (`mall-sandbox.zip`), fresh copy, own slot, build while paused.
- RCON blocks are flattened to one line: whole-line comments only.
- `helpers.write_file(name, data, false, 0)`.
- `bench.lua` owns `script.on_nth_tick(1)` while it runs; never call `H.run` at the same time.

## Review focus

1. A cell's dump counted as product (or the reverse) around a recipe change → robot item counts wrong.
   Rule: a dump is whatever appears in the cell's `assembling_machine_dump` inventory.
2. The ideal tree picks a different recipe than the cells use → wrong optimum. The JSON records
   the cells' actual recipes; `analyze.py` warns on any mismatch.
3. Electric statistics units (J per tick vs per second) → energy off by 60×. Verified in-engine
   against an assembler's nameplate draw.
4. A run that hits the cap before 50 → report "not reached", never a time.
5. Stock already on hand → the ideal is net of starting stock; a test pins it.

## JSON (`script-output/bench_<tag>.json`)

```
tag, target, n, cap, t_end, ended ("idle" | "cap"), t_made_n, t_delivered_n (nil if not reached)
cells:   [{x, y, speed, prod}]                       C1..C20 in H.cells() order
recipes: {name: {energy, ingredients: [[item, n]], products: [[item, n]]}}
tree:    {item: recipe}       recipe the ideal uses for each made item (mask item with an AM2 recipe)
stock0:  {item: n}            network stock of every tree item at start
events:  [[t, cell, "r", recipe or "-"], [t, cell, "s", status], [t, cell, "c", recipe, n], [t, cell, "d", item, n]]
samples: [{t, j: {prototype: cumulative J consumed}, held: [items in cell i's requesters + input]}]
types:   {prototype: entity type}
```

## Tasks

### Task 1: `analyze.py` core, test-first

**Files:** create `bench/analyze.py`, `bench/test_analyze.py`.

- `ideal(run) -> {crafts: {recipe: n}, time: ticks, chain: ticks}`: expand `n` × target through
  `tree`, net of `stock0`, crafts = ceil(need ÷ (product × (1 + mean prod))); time =
  Σ crafts × energy × 60 ÷ Σ cell speeds; chain = longest energy × 60 ÷ max speed path.
- `cell_buckets(run) -> [{useful, switching, starved, full, none, surplus}]` in ticks:
  switching = recipe change until the first craft of the new recipe; surplus = crafts of a recipe
  after the ideal's crafts of it are used up (in time order), as craft-ticks.
- `energy(run) -> {by_type: {type: J}, robot_items, ideal_robot_items, ideal_robot_j}`.
- Tests (`python -m unittest bench/test_analyze.py`) on a 2-cell synthetic run:
  - `test_ideal_net_of_stock`: target A = 2 B; stock0 B = 2, n = 2 → crafts {A: 2, B: 1}.
  - `test_switching_until_first_craft`: change at t = 10, first craft at 40 → switching 30.
  - `test_surplus_after_need`: 3 crafts of B where ideal needs 1 → 2 surplus.
  - `test_energy_by_type`: cumulative samples 0 → 600 J roboport, 0 → 60 J inserter → 600 / 60.

### Task 2: HTML report

`render(runs) -> str`: score row (t delivered, t idle, perfect and realistic optimum and %, MJ total,
MJ per target, ideal MJ, by type), timeline SVG (lane per cell, colour = recipe, light = not
working, black tick = switch, energy strip below; several runs stacked on one time axis), per-cell
table. CLI `python bench/analyze.py run.json [other.json] -o report.html`.
Test: `test_render_smoke` — output contains every cell label and both tags.

### Task 3: `bench.lua` recorder, verified in-engine

`BN.start(tag, target, n, cap)`, `BN.done`, `BN.save()` → writes the JSON. Cells' chests found from the
inserters whose drop or pickup target is the cell. Verify on a sandbox copy with r6: the run ends,
the JSON loads, energy units checked, the report renders.

### Task 4: docs

`bench/README.md` (commands), one line in the mall `README.md` Tools section.
