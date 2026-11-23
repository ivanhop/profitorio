# Round 3 overview

Base design: **hardened B** (`r2-b/build.lua`, 155 combinators): 82% working over 3600 ticks with
21 changes, and research servers actually get built. Goal and tools: `README.md`.

## Decisions going in

- **Fast inserters stay.** No bulk-inserter swap.
- **No commanded-recipe chest requests.** No combinator turns a recipe into its ingredients. The
  probe-assembler workaround would save at most about 6% once a cell holds its recipe longer.
- **Grace until first craft replaces a flat minimum hold.** B's budget counts from the moment of a
  switch, so it is empty after 120 ticks, long before the first delivery (about 450). From now on the
  budget starts counting only after the cell's first finished craft of its new recipe, or after
  900 ticks, whichever comes first. One extra condition on the existing counter.
- **Priority:** the item leaves the list > grace > starvation budget > jumping to an unstaffed item.
  A cell whose item is done is freed at once. Nothing else moves a cell during its grace.

## Agents (15 minutes each, progress check every 5 minutes)

| Agent | Change on top of r2-b | Question it answers |
|---|---|---|
| **r3-grace** | Grace until first craft (cap 900), with the priority order above. Measured with grace on and off. | Does protecting the switch-in cut churn and raise working %? |
| **r3-second** | A slow item that already has its one cell can get more: allow a second cell when the item's sole cell is working and its shortage stays high. Measured on and off. | Does it lift advanced circuits and the server out of the bottleneck and shorten time-to-10? |
| **r3-reference** | No design change. Runs the full scorecard below on r2-b and on design C, under the paused harness. Also runs batch-and-idle. | Comparable reference numbers, and whether a batch really ends idle. |

Every agent copies `r2-b/build.lua` (r3-reference also uses `design-c/build.lua`) into its own
folder and edits only that copy.

## Scorecard (every agent reports all rows that apply)

All runs start from a fresh copy with the harness loaded, which pauses the game. Build while paused;
`H.run` unpauses.

| # | Metric | How |
|---|---|---|
| 1 | **S1 working %**, changes | `H.run(600,"s1")` |
| 2 | **Time to first 10 research servers**, plus the time to the first one | `H.run(3600,"t10")` on a fresh build, measured from the demand start. The report line `first 10 kr-research-server: ... ticks`. "NOT reached (k made)" if over 3600 |
| 3 | **Long-run working %**, changes, per-recipe split | Same 3600-tick run as #2 |
| 4 | **Batch-and-idle**: ticks from demand cleared until all 20 cells have no recipe; hoard and leftover stock after | `H.demand()`, then `H.run` in 600-tick slices until idle or 3600 (r3-reference only) |
| 5 | **Combinators** per cell and at the head | Count |

`H.run(ticks, tag, target, n)` defaults to `kr-research-server` and 10.

**Baseline (current 0.2.7 mall, 3600 ticks):** working 10%, 135 changes, first server at 79 ticks
(already-loaded ingredients), **10 servers not reached** (1 made).

## Rules carried over (lessons from rounds 1–2)

- Each agent gets its own slot and a private scratch folder (`scratchpad\r3-<name>\`) with the port
  hardcoded. It never uses shared file names.
- `helpers.write_file(name, data, false, 0)`.
- Wires ≤ 9.75 tiles. Mask via `mask.lua` + `H.set_mask`. Buffer = stack ÷ 4.
- Short tests. Only #2–#4 need 3600 ticks.
- Hard stop at 12 minutes to write notes. Reply to progress checks with SendMessage.
- An "it would work by wiring" claim must be built or measured, not simulated by script. If it
  was simulated, say so.
