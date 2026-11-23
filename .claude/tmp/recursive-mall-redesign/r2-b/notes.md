# Round 2, design B hardened

`build.lua` runs after `harness.lua`, `mask.lua` and `H.rig_off()`. Knobs as in round 1, plus
`MB.FALLBACK` (default 0 = off) and `MB.RECOVER` (default true). `blueprint.txt` is the mall block
from the final fresh build. No wire in it is longer than 9.75 tiles (checked in-engine).

## Delta from round 1

- **Mask:** `H.set_mask(hd.mask)` loads the 367 items. `kr-steel-beam` now gets cells, and the
  research server is crafted (10 in the long run).
- **Budget recovery (kept):** the assembler's recipe-finished pulse is `signal-R` on the A net.
  K gets a second condition, `R = 0`, so a finished craft drops K's output for one tick and the
  budget returns to 0. Only a cell that makes nothing for BUDGET ticks walks down. 0 extra
  combinators.
- **Raw-input fallback (built, off by default):** an OR clause on T. Once `B <= -FALLBACK`, T
  boosts `signal-dot`, the only Q0 value in 50000..299999. An ingredient boost still wins. 0 extra
  combinators. Measured as harmful, see below.
- **Wire cap:** `MB.net` (Prim) never links two nodes more than 9.75 tiles apart, and asserts if a
  node is out of reach. The O bus needed a relay pole at (-220.5,103.5): `hd.an` to the nearest
  latch was 9.92 tiles.
- **Count:** 7 per cell + 15 head = **155 combinators**, unchanged. Plus 1 relay pole.

## Scorecards

The final build, on a fresh copy (server3):

| Run | Working | Recipe set, not working | No recipe | Changes | Hoard |
|---|---|---|---|---|---|
| S1 600 | 9% | 73% | 18% | 58 | 114 |
| S2 600 | 46% | 42% | 12% | 21 | 446 |
| long 3600, demand on | **82%** | 16% | 2% | **21** | 1042 |

Long-run split (average cells): components 17.35 / AC 0.98 / server 0.99 / blank tech card 0.35.
The run made 225 components, 12 AC and 10 servers. No cell changed more than 4 times.

**S1 is noisy across copies.** An earlier fresh copy of the same build with FALLBACK=240 gave S1 at
42% and S2 at 59%. Each `instance.ps1` copies the live save, and its tick differs between copies,
so S1's start state is not fixed. Only compare S1 numbers taken on the same copy.

**A/B on one server, sequential 1800-tick segments, demand on:**

| Variant | Working | Changes | Servers made |
|---|---|---|---|
| fallback on, recovery on | 59% | 84 | 6 |
| fallback off, recovery on | 63% | 13 | 7 |
| fallback off, recovery off | 46% | 77 | 4 |

The segments ran one after another, so the state drifts. The size of the change-count gaps is
still unambiguous.

- **Fallback to idle is worse than "stay".** The cells that leave are surplus component helpers
  starving on robot-delivered raw inputs. Once idle, they re-pick the top of Q0, which is the
  server: it has the highest F-class score with one cell. They starve there, walk down to AC,
  then to components, and starve again. With 4 cells in that loop, the 3600-tick run on the first
  copy logged 102 changes. Staying starved costs the same throughput and makes no dumps. That is
  why the default is off.
- **Recovery helps clearly:** 63% against 46%, and 13 changes against 77. Without it, any
  ingredient blip walks a long-working helper away.

## Does S2 end?

Not within the test window. With demand cleared, the hysteresis keeps the batch on F until there
is stock of B = stack/4. The server batch makes about 7 servers per 1800 ticks, and the 2-cell
server/AC chain is the bottleneck. So the batch takes on the order of 10k+ ticks to finish, and
idling after it was not measured this round. (Round 1 measured batch-then-idle on power switches:
0% work, 0 changes, hoard 0.)

## Weakness / open problems

- **The split follows shortage counts, not throughput.** Components get 17 cells and AC and the
  server 1 each (the sole owner). The 1-cell server and AC are the batch bottleneck, while about
  half the component cells starve on raw inputs (16% recipe-set-not-working). B has no way to
  push a second cell onto a slow sole-owner item: its F class only drops by 1000 per cell.
- **No good raw-input fallback yet.** Idle-then-re-pick herds. A real fix needs an "idle cells
  only take items whose own ingredients are in stock" rule, or a cooldown on the idle candidate.
- Hoard grows with the requested buffers: 1042 items in the long run.
