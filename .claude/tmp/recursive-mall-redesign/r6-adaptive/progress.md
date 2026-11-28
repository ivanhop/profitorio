# Round 6 progress

- Designed the re-arm latch: L = X1 OR (L AND stock ≤ B/2), with Q = B/2 − stock feeding it. The
  edge moved from X1 to L. Done.
- First build failed: `MB.net` refused the Bmem wire (> 9.75 tiles), because `spot` scattered 7
  combinators on both sides. Fixed by searching outward from the last placed combinator. Built: 7
  combinators, 17 wires.
- Measured the 50-server run on/off in parallel (slot 4 off, slot 5 on). Done.
- Measured the 5-server batch to idle plus a second batch. On: idle at 8400 t. Off: its first copy
  was orphaned by a `Start-Job` whose session ended, so I stopped that server and reran it alone.
  Idle at 8400 t. Done.
- All my servers (slots 4 and 5) are stopped. Scripts and logs are in the scratchpad `r6-adaptive`
  folder (`drive.ps1`, `out-*.txt`).
