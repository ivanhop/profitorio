# Recipe-switch cost: measured anatomy (slot 6, colin 0.2.7, cell C1)

Method: C1's red recipe wire was rerouted to a test constant combinator. Each switch was set by circuit,
and the cell was logged every tick (recipe, dump, input, hands, status). The other 19 cells kept running.

## Anatomy of one switch (switch at t=0)
| Phase | Measured | What sets it |
|---|---|---|
| 1. finish the craft in progress | 0-30 t (gear) | the old recipe keeps running until its current craft ends |
| 2. recipe reads "-" while the dump drains | 12 t/item with the fast inserter (2 items per 24-tick swing) | everything in the input slots goes to the dump: 4-11 plates for gear/cable = 50-130 t; 41 items for kr-research-server = **500 t** |
| 3. robot delivery of B's ingredients | **270-320 t** | chest requests come from the assembler's *actual* recipe (green -> selector stack-size), so they start only after phase 2. Dispatch is immediate (<3 t); robots leave the roboport at (-213,133) and pick up at the kr-storage-warehouse (-208,135), 33 tiles away at 0.121 tiles/t, so about 270 t. Pure distance, not robot availability (776 of 795 idle). |
| 4. insert and craft | about 25 t + one craft | |
Totals, switch to first B craft: gear->cable 520 t, cable->gear 438 t (fast inserter). First switch away from research-server: 500 t of "-" alone.

Observed but no lever: the dump always takes the whole input, even when B shares the ingredient (gear->pipe dumped 11 iron plates).
Chest leftovers never blocked: no input inserter got stuck holding an A item, and robots trash the chest leftovers in parallel.
So smaller chest requests or trash-unrequested do not change the switch time: the dump size is the assembler's own input fill.

## Remedies tried
| Remedy | Physical change | Effect |
|---|---|---|
| Bulk inserter as the output inserter | swaps 1 inserter per cell (20 bulk inserters; the network has 0, the recipe is researched) | hand 2 -> 5, same 24-t swing: dump 12 -> about 5 t/item. 11-item dump 132 -> about 72 t; a 41-item dump drops from about 500 to about 200 t |
| Stack-size override | none | it can only *lower* the hand size, so it is useless here |
| Prefetch: request B's ingredients in the chests at the moment of the switch (tested via a script section; in hardware, the selector would read the *commanded* recipe) | wiring only | robot leg overlaps phases 1+2: first craft at 309-325 t instead of 420-520 t (saves about 80-200 t, the dump time) |
| B's ingredient already in the chests (gear->pipe, both iron) | none | **142 t** to first craft: no robot leg, only finish + dump + insert |
| Passive provider with plates 3 tiles from the cell (test only) | +1 chest | ignored: the robots still picked up at the warehouse 33 t away. Inconclusive; a storage chest next to the mall might work, untested |

## Recommendation for the controllers
- Budget a switch at about **450 t** (one dump of about 10 items plus a 33-tile robot leg); a switch away from a many-ingredient recipe costs up to about 800 t.
- **Minimum hold of 1800 t (30 s)** per assignment keeps switch loss to about 20%; 3600 t gets about 12%. Never re-assign a cell that switched less than about 600 t ago: it hasn't crafted yet.
- Prefer handing a cell a recipe whose ingredients its chests already hold (cost about 140 t vs about 450 t). In a recursive mall that means intermediates (plates/gears/cables) stay with their consumers.
- Cheap hardware wins, in order: (1) drive the chest requests from the commanded recipe, not the assembler's live recipe, so the robots fly during the dump (wiring, -80..-200 t); (2) bulk output inserters (20 swaps, dump time -60%); (3) worker-robot speed research or a storage chest near the mall for the 270-t leg (not measured).
