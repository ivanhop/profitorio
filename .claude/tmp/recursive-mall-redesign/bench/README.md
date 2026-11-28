# Mall benchmark

Scores a run of 50 beacons against the computed optimum, in time and energy, per cell, with a
timeline of what every cell crafted. Design: `DESIGN.md`.

## Run

```bash
R="python tools/check/probe_client.py --host 127.0.0.1 --port 2712N --password probe"
D=.claude/tmp/recursive-mall-redesign
$R < $D/harness.lua; $R < $D/mask.lua; printf '/silent-command H.rig_off()\n' | $R
$R < $D/r2-b/build.lua            # the design under test (plus e.g. r6-adaptive/build.lua)
$R < $D/bench/bench.lua
printf '/silent-command rcon.print(BN.start("r6", "beacon", 50, 54000))\n' | $R
printf '/silent-command rcon.print(BN.status())\n' | $R      # repeat until "done"
python $D/bench/analyze.py <instance dir>/script-output/bench_r6.json [other.json ...] -o report.html
```

- Start a fresh `mall-sandbox.zip` copy per run (`instance.ps1 -Save`). Never call `H.run` while
  `BN.start` is running: both use `on_nth_tick(1)`.
- The run ends when 50 have arrived in the trigger chest **and** every cell has no recipe, or at the
  cap. A capped run reports "cap hit": its idle time is unknown.
- `beacon` is not researched in colin0.2.7. `BN.start` unlocks the recipe on the copy and says so.
- `BN.start` removes every ghost on the copy. The sandbox keeps the save's 11 ghosts, all beacons;
  left in place, construction robots build them from the batch (measured: 61 made, 48 delivered,
  +5.28 MW of beacon draw), and the cells near them speed up mid-run.

## What the numbers mean

- **Perfect**: the beacon tree's crafts, net of starting stock, spread over all 20 cells at their
  real speed, with no switches and no travel. Never below the longest single chain.
- **Realistic**: perfect plus the wait before the run's first craft (the first robot delivery).
- **Per-cell buckets**: useful; **surplus** (crafts beyond what the batch needed, e.g. buffer
  refills); **switching** (no craft yet since the recipe change); starved; full; other; none.
- **Energy**: the mall's electric network, by entity type. Robots charge at roboports, so robot
  energy shows up as `roboport`.
- **Robot items**: items into cells (ingredients consumed, dumps, change in held stock) plus items
  out (products, dumps). The ideal counts each ingredient and product of the ideal crafts once.
  **Ideal robot MJ** = measured MJ per robot item × ideal items: an estimate, not a model of distance.
- A red warning means the cells made a tree item with a different recipe than the optimum assumed.

`python -m unittest test_analyze` (from this folder) tests the analyser on synthetic runs.
