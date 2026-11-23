# r3-reference: measurements only, no design change

Slot 6. Load order on every copy: harness.lua, mask.lua, H.rig_off(), build.lua. Neither build loads the harness
itself. Design C: after the build, `H.set_mask` was called on its mask combinator at (-216.5,137.5) (367 items).
Copies: r2-b S1 = copy 1; r2-b t10 + row 4 = copy 2 (row 4 continues on from the t10 run); C S1 = copy 3;
C t10 + row 4 = copy 4. S1 never shared a copy with t10.

| Metric | r2-b | design C (+ new mask) |
|---|---|---|
| 1. S1 working %, changes (600 t) | 11%, 57 | 35%, 27 |
| 2. Time to first 10 servers / first one | NOT reached (8 made) / 1529 t | NOT reached (6 made) / 1240 t |
| 3. 3600 t working %, changes | 70% (21% recipe-not-working, 9% none), 108 | 68% (26% / 6%), 42 |
| 3. Split comp / AC / server / card / beam / cable (avg cells) | 14.19 / 0.81 / 1.22 / 1.53 / 0.05 / 0.45 | 12.52 / 2.82 / 1.22 / 1.95 / 0.35 / 0 |
| 3. Crafts comp / AC / server / card | 178 / 0 / 8 / 25 | 132 / 37 / 6 / 49 |
| 3. Hoard at end of t10 | 919 | 748 |
| 4. Ticks to idle | NOT idle at 3757 (20 cells with a recipe) | NOT idle at 3777 (20 cells with a recipe) |
| 4. Hoard / stock server, AC, comp at end | 986 / 12, 10, -19 | 1026 / 12, 126, -16 |

## Row 4 slices (after H.demand(), every 600 t: cells with a recipe, hoard, server/AC/comp stock)

- r2-b: 20, 1078, 1/60/-40 -> 20, 980, 4/32/5 -> 3, 404, 5/0/79 -> 17, 558, 8/-6/-31 -> 20, 901, 3/6/-32 -> 20, 986, 12/10/-19.
  Came close to idle at ~1870 t (3 cells), then 17-20 cells picked up recipes again. Last slice: 79% working, 0 changes.
- C: 20 cells with a recipe in every slice; hoard climbed 814 -> 1026, AC stock climbed 54 -> 126.

## Anomalies

- **Neither batch ends idle.** After `H.demand()` the trigger is empty (checked), and the network has no requester
  asking for kr-research-server (checked: the only AC/server requests left are four cell chests at
  x -228/-222, y 134-136 with advanced-circuit = 10). The server stock still bounces (12 -> 1 -> 10), so servers are
  being taken somewhere, or the "missing" signal still counts something. Not diagnosed (no time). Suspect either the
  cell chests' own requests feeding the head's demand, or a hysteresis latch that never drops.
- r2-b crafted **0 advanced circuits** in the 3600 t run while holding 0.81 cells of it on average; the 8 servers used
  AC from stock. C crafted 37 AC on 2.82 cells. AC remains the bottleneck for time-to-10 in both.
- Component stock reads negative (-16 to -40): `get_item_count` net of robot reservations.
- Copy 3 (C S1) reported `H` already defined before the harness was loaded, though its tick (3356920) shows a fresh
  load. The harness was loaded again anyway; the numbers should be unaffected.
- Row 5 (combinators) not counted; from the README: r2-b 155, C 92.
