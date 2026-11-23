# Round 3, r3-second: a second cell for a slow item whose cells all work

`build.lua` is `r2-b/build.lua` plus block 5. It is switchable: set `MB = {SECOND = false}` before
loading to get plain r2-b (block 5 prints "second: off" and builds nothing). `MB.SECOND_D` (default
0) is the minimum D that counts as "short".

## Delta (built in real combinators, verified in engine)

- **WK, one decider per cell** (free slot f[7]). Red in = the L latch (recipe item), green in = the
  A net (budget signal-B). `EACH > 0 AND B > -BUDGET` gives `EACH = 1001` on a new DIFF bus.
- **an2, head arithmetic**: O bus × -1000 onto DIFF. So per item
  DIFF = 1001·working − 1000·cells: > 0 only when every cell on the item is working; < 0 as soon as
  one starves; 0 when unstaffed. Read in engine during S1:
  `server=-994 advanced-circuit=-3000 components=-1995 blank-tech-card=3`.
- **BN, head decider**: `D > SECOND_D AND DIFF > 0` puts −150000 on Q0. That parks the item in
  Q0 300000..450000, a range no other value uses, and lowers it for fresh (idle) cells.
- **T gets an OR clause** (0 combinators): `Q0 in (300000, 450000) AND B <= -BUDGET` gives the
  1e6 boost. So only a *spent* cell sees the item at ~1.35e6: above the 999999 hold of a shared
  cell, below an ingredient walk-down or an unstaffed item (~1.5e6). Sole holders (2e9) never
  move, and working helpers never move. Priority: walk-down > unstaffed > working bottleneck > stay.
- DIFF crosses the bottom on 3 new poles at y 140.5. All wires go through `MB.net` (≤ 9.75).
- **Count: 8 per cell + 17 head = 177 combinators** (r2-b 155), plus 3 poles.

## Scorecard (incomplete: the time limit was hit)

| Run | S1 working | S1 changes | First server (S1) | t10 (3600) | 3600 working | Combinators |
|---|---|---|---|---|---|---|
| SECOND on (copy A) | 13% | 61 | 30 ticks, 1 made | not measured | not measured | 177 (8/cell + 17 head) |
| SECOND off (copy B, = r2-b) | 21% | 41 | none made | not measured | not measured | 155 (7/cell + 15 head) |

S1 split, on: components 7.54, AC 2.88, server 2.19, blank card 2.27 (avg cells).
S1 split, off: components 8.10, AC 1.20, server 1.95, blank card 3.71, steel beam 1.13.
**The two S1 numbers come from different copies.** r2-b notes show S1 swinging between 9% and 42%
across copies, so a 13% vs 21% gap does not show the mechanism is better or worse. There is also a
caution: AC held about 3 cells with the switch on against about 1 with it off, and in S1 all of them
were starving (DIFF `advanced-circuit=-3000`).

## Not measured, and why

- **Time to first 10 servers, and 3600-tick working %: not measured, on or off.** The first t10
  attempt hung: a restart wrapper piped `instance.ps1` into `tail`, which waits on the server's
  stdout. The second attempt's copy failed in block 5 with "attempt to index field '?'". The output
  was cut by `tail -1`, so an earlier block may have failed first. I stopped it.
- No `blueprint.txt`: there was no time left for a clean build plus `H.export`.

## Open problems

- **The 3600-tick run is the real test.** The mechanism only acts on cells that have spent their
  budget, and it pays off once the AC and server cells actually craft. A 600-tick S1 says little.
- **A failure mode to watch: one starving cell blocks the second cell.** DIFF > 0 needs *every*
  cell on the item working. A bottleneck item whose sole owner starves on a raw input never gets
  a second cell, which is correct. But if any one helper on it starves, the bonus is lost for all
  of them.
- **Fresh (idle) cells now see a bottlenecked item 150000 lower in Q0.** Idle is 2% of cell time
  in r2-b, so this should be minor. It is unmeasured.
- **Churn is bounded by the budget.** A spent helper moves at most once per BUDGET (120) ticks of
  no crafting. On its new item it starts with a fresh budget and counts as working until it is
  spent. Unmeasured over 3600 ticks.
