# r4-adaptive progress

- Built: `build.lua` (5 combinators, 11 wires on top of r2-b), loads cleanly on the sandbox.
- Measured: 3600-t on/off pair and 5-server batch-to-idle pair, fresh copies, slots 4/5 in parallel;
  B logged every 600 t. All numbers in `notes.md`. Nothing simulated.
- State: all servers stopped. Open: the stockout edge definition (D > 0 edge grows B during every
  batch); a stock ≤ 0 edge or decay is the next thing to try.
