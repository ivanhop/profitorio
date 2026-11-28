# r5-adaptive progress

- Built: `build.lua` = round 4 with X1 changed to (D > 0 AND stock = 0 on hd.neg's red output), one
  new wire hd.neg output red -> X1 input red. Still 5 combinators added; 12 wires.
- Measured: 3600-t on/off pair and 5-server batch-to-idle pair, fresh copies, slots 4/5 in parallel,
  distinct tag per chunk, B logged every 600 t. Numbers in `notes.md`. Nothing simulated.
- State: all servers stopped. Verdict: the edge does not stop runaway growth (re-fires on each pass
  through zero); next try is re-arming only after refill to B/2, or decay.
