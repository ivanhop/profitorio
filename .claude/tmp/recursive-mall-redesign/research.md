# Recursive mall (save colin0.2.x): research and redesign

This is unrelated to Profitorio. It is a circuit-controlled mall in the user's Space Age + Krastorio2
playthrough. Everything below was measured on copies of the save in an isolated headless server; the
real save was never touched.

> **Session 2 (2026-11-23):** tooling (`instance.ps1`, `harness.lua`), the goal, the standard
> scenario and the baseline score are in `README.md`. Three rival designs were built in parallel;
> each has its own `design-a|b|c/notes.md`. Read the README first.

## 0. How to use the colin0.2.7 save (next session start here)

The save belongs to the user's real Steam game. **Never open, modify or run the game against
`%APPDATA%\Factorio` itself.** The user may be playing at the same time: another `factorio.exe` from
Steam can be running. Never kill a process you did not start. Always work on a copy, inside an
isolated write-data directory.

**Facts**

- Save: `%APPDATA%\Factorio\saves\colin0.2.7.zip` (22-11-2026 21:58). Copy it, never use it in
  place.
- It needs the **Steam** Factorio **2.1.24** binary with Space Age:
  `C:\Program Files (x86)\Steam\steamapps\common\Factorio\bin\x64\factorio.exe`. The repo's
  `factorio/` install is 2.1.14 and cannot load the save.
- It needs about 75 mods (Krastorio2, Space Age, etc.), taken from `%APPDATA%\Factorio\mods`
  (≈3.7 GB). **Hardlink** them, don't copy. Factorio never writes into mod zips. Hardlinked zips may
  be locked while the user's game is running; leave them be.
- Logistic network 18 on nauvis, mall block x −243..−216, y 103..137 (details in §1).

**Setup** (PowerShell; `$w` is any new empty directory, e.g. under the session scratchpad)

```powershell
$w = "<new empty dir>"
New-Item -ItemType Directory -Force "$w\mods","$w\saves","$w\config" | Out-Null
Get-ChildItem "$env:APPDATA\Factorio\mods" -File -Filter *.zip | ForEach-Object {
  New-Item -ItemType HardLink -Path "$w\mods\$($_.Name)" -Target $_.FullName | Out-Null }
Copy-Item "$env:APPDATA\Factorio\mods\mod-list.json","$env:APPDATA\Factorio\mods\mod-settings.dat" "$w\mods\"
Copy-Item "$env:APPDATA\Factorio\saves\colin0.2.7.zip" "$w\saves\colin.zip"
$wf = $w -replace '\\','/'
"[path]`nread-data=C:/Program Files (x86)/Steam/steamapps/common/Factorio/data`nwrite-data=$wf" |
  Set-Content "$w\config\config.ini" -Encoding utf8
# The server-settings file must be complete (a minimal file fails: Key "description" not found).
Get-Content "C:\Program Files (x86)\Steam\steamapps\common\Factorio\data\server-settings.example.json" -Raw |
  ConvertFrom-Json | ForEach-Object { $_.auto_pause=$false; $_.visibility.public=$false;
  $_.visibility.lan=$false; $_.require_user_verification=$false; $_ } |
  ConvertTo-Json -Depth 5 | Set-Content "$w\server-settings.json"
```

**Start the headless server with RCON** (it loads in about 10 s; wait for `Starting RCON` in out.txt)

```powershell
$exe = "C:\Program Files (x86)\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
$p = Start-Process $exe -PassThru -NoNewWindow -RedirectStandardOutput "$w\out.txt" -RedirectStandardError "$w\err.txt" `
  -ArgumentList @("--config","$w\config\config.ini","--start-server","$w\saves\colin.zip",
  "--server-settings","$w\server-settings.json","--rcon-bind","127.0.0.1:27123",
  "--rcon-password","probe","--port","34299","--disable-audio")
$p.Id | Set-Content "$w\pid.txt"   # stop later with Stop-Process -Id <that pid> only
```

`auto_pause=false` matters. Without it a server with no players never advances a tick.

**Query it** (Git Bash, from the repo root): write the Lua to a file and pipe it in. Never pass
`/command` as a bash argument, because Git Bash mangles a leading slash.

```bash
cat > "$S/q.lua" <<'EOF'
/silent-command rcon.print(game.tick)
EOF
python tools/check/probe_client.py --host 127.0.0.1 --port 27123 --password probe < "$S/q.lua"
```

- **One command per line.** The client flattens a block, so a `--` Lua comment swallows the rest.
  Separate commands with a line containing only `---`.
- `serpent.line` is available. Directions are 16-valued (N0 E4 S8 W12).
- Two servers at once need separate write-data dirs and different `--rcon-bind`/`--port`, e.g.
  27124/34300.

**Testing conventions (user preference)**

- Tests are **a few seconds of game time**. Go longer only if the pattern needs it.
- Record per tick with `script.on_nth_tick(1)` on your own copy and log changes only.
- Assert observable effects: recipe per cell, `products_finished` deltas, status, chest requests.
  Settings read back from combinators do not prove anything works.

**Reproducing the trigger:** the user's request is the manual requester at (−207.5,122.5),
kr-research-server 50. Players are offline in a headless server, so their personal "Basic"
logistic group does not request. The test rig's chest at (−222.5,148.5) pollutes the main list
(bug #2); switch its requests off in the copy.

**Cleanup:** `Stop-Process` on your own PID, then delete the work directory. Hardlinked zips that
are locked by the user's game can be left until it closes.

## 1. Current design (colin0.2.7)

Location: nauvis, combinator block x −243..−216, y 103.5..136.5. It has 20 cells. Cells C1–C10 run
down the right column at x = −224.5, y = 108.5 … 135.5. Cells C11–C20 run up the left column at
x = −234.5, y = 135.5 … 108.5. Every cell is wired identically.

### Head (list source)

- Roboport (−219,105) reads the logistic network **contents**. A decider (−221.5,105) keeps only
  values > 0, then an arithmetic combinator multiplies by −1, giving −stock.
- Roboport (−226,105) reads **missing requests**, giving +missing.
- The mask is constant combinator (−223.5,106.5): 179 items, each set to 1. Two arithmetic
  combinators, (−222.5,105) and (−223.5,105), multiply mask × −stock and mask × missing.
- A decider (−223,103.5) keeps values > 0. The result is the **list on green net 3**:
  masked items where `missing − stock > 0`.

### Cell

1. A selector (max, index 0) picks the biggest item on the cell's incoming list.
2. The latch-set decider loads that item into the red latch, but only while the latch is empty.
3. The latch-hold decider keeps the latched item only while that item is still on the cell's
   **own incoming list**.
4. An arithmetic combinator (×1) sets the assembler's recipe on **red only**. The assembler reads
   its ingredients onto **green only** (fixed since 0.2.5).
5. A stack-size selector turns those ingredient signals into requests on the cell's
   **4 requester chests: one full stack of every ingredient in each chest**.
6. The outgoing list is the incoming list with the latched item removed. The pass-through path and
   the removal path are both 2 ticks long, but the claim itself is decided 1 tick late.

### Chain order (list nets)

3 → 16 → 61 → 8 → 24 → 34 → 50 → 41 → 19 → 23 → 4 → 32 → 12 → 9 → 10 → 18 → 28 → 6 → 7 → 13 → 94.
Net 94 is the end of the chain and nothing reads it.

## 2. Bugs found

| # | Save | Symptom | Cause | Evidence |
|---|---|---|---|---|
| 1 | 0.2.5 | Electronic and advanced circuit cells flip to copper cable every 2 ticks and request 4×200 cable | Read-ingredients was echoed onto the set-recipe wire. Recipe selection goes by **signal order, not value**, and copper-cable sorts before electronic-circuit. | 466 recipe changes in 1600 ticks. With the echo turned off as a control: stable. **Fixed in 0.2.7** by splitting the wires red/green. |
| 2 | 0.2.7 | C4 (−224.5,117.5) switches between idle and copper cable every 1–4 s ("unknown request") | The test rig at y≈139–150 shares logistic network 18. Its list comes only from negative contents (robot reservations), because its missing-requests roboport (−225,146) is not wired into the arithmetic combinator (−222.5,146). Its chest (−222.5,148.5) sets cable/EC/components to 200 for 40–160 ticks at a time, which appears one tick later in the main missing-requests count. | Rig chest requests switched off as a control: the flip stops. Cell C2's cable chests switched off instead: the flip continues (15 cycles in 60 s). |
| 3 | both | Cells latch and release items briefly | There is no hysteresis. The latch releases as soon as the item leaves the cell's own incoming list, and the list follows robot-reservation noise (stock −18 … +56). | Logged per tick. |
| 4 | both | Downstream cells latch an item for 1 tick when it appears | The claim is removed 1 tick later than the list passes through. | Ripple runs 1 → 7 → 11 → … across idle cells. |
| 5 | both | Heavy robot traffic and sub-item over-demand | Every chest requests a full stack per ingredient. 4 chests × 200 = 800 cable for a single circuit cell. | |
| 6 | rig | Assembler (−217.5,139.5) flips between cable and advanced circuit | It has bug #1: no latch, and both wires are used for reading and writing. | |

Known but ignored for testing: steel beams and blank tech cards are not on the mask.

## 3. Engine facts (official docs and in-engine measurements)

- Set-recipe ignores signals ≤ 0. A recipe signal wins. Otherwise item signals map to recipes in
  **recipe order** (category → subgroup → order → name), not by value. With no match the machine
  goes idle (`factorio-docs/markdown/auxiliary/circuit-recipe-selection.md`).
- Set-recipe is applied only when a craft finishes. On a recipe change, leftover ingredients go to a
  dump inventory (FFF-394).
- Roboport read modes: `logistics` (contents), `missing_requests`, `none`. "Missing" means the
  amount needed to satisfy all requests, including players and spidertrons but not construction
  (FFF-428).
- In-engine: roboport contents go negative only briefly, while robots hold stock reserved.
  A request for an item with zero stock does not show in contents at all.
- Copper cable: 1 copper plate makes 2 cable. Stack size 200.

## 4. Redesign (agreed, not built; see 4.6)

### Decisions so far (user)

- **Helpers are assigned by starvation** (Option C below). There is no one-at-a-time turn-taking.
- **"Starving" = the assembler has a recipe and is not working** ("Read working" off). There is no
  inbound check and no chest fill ratio. Robot speed is handled by giving the network enough
  robots and roboports, with chest requests sized from crafting speed (4.3) so that they cover the
  robots' round trip.
- **Starvation is a total budget, not a sliding window.** Each helper assignment starts with a
  budget, e.g. 300 ticks. Every starved tick spends 1. When the budget is empty, the helper leaves
  and re-picks (see the next bullet). The budget resets only when the helper takes a new item.
  - Consequence (my note): a helper that starves only a little still leaves eventually. At 2%
    starvation a 300-tick budget lasts about 250 s. This works as a slow periodic rebalance.
- Owners never leave because they are starving. Only helpers do.
- **A helper that leaves picks its next item with no intelligence.** It does not target the
  ingredient. Rule: item index = `(cell number + times this helper has left) mod (items on F)`, taken
  from F with a selector.
  - The counter guarantees it moves to a different item, instead of re-picking the one it just
    starved on.
  - The ratio still emerges by selection: helpers on starving items keep leaving, and helpers that
    land on the bottleneck ingredient keep working and stay.
  - Cost: convergence is slower. Each wrong guess costs up to one starvation budget (~5 s), and
    with a short list of 3–6 items a few rounds are enough.
  - Cost per cell: 1 leave counter, 1 modulo, 1 selector. This replaces the ingredient-capture
    logic.

### 4.1 List with hysteresis (head)

- Keep the balance **D = missing − stock** per item: D > 0 means a shortage, D < 0 means a surplus in
  storage.
- Add a per-item memory (each-signal latch) as a thermostat:
  - **On** when D > 0.
  - **Stays on** while D > −B, so until storage holds a surplus of B.
  - Output **D + B** = the amount still to make.
- B defaults to **1 stack** (stack-size selector on the mask). One arithmetic combinator scales it,
  e.g. ×½ or ×2.
- Effect: a request builds the request plus one stack. The next few requests are served from
  storage, and reservation noise never reaches the cells.
- Rejected alternative, an "order chest" (a requester chest storing demand × k): items in a requester
  chest are locked away from the network, and the chest's own request returns through missing
  requests and gets counted twice.

### 4.2 Two lists down the chain

- **F (full)**: every item that is switched on. It is never reduced.
- **R (remaining)**: unclaimed items. Each owner claim removes its item.
- What a cell does:
  - **Owner**: when the latch is empty, it takes the top of R. It holds the item until the item
    **leaves F**, so through a whole batch. It is no longer released when the item leaves its own
    incoming list.
  - **Helper**: when R is empty but F is not, it takes an item from F (see 4.4 for how).
  - **Preempted**: a helper switches to a new item that appears in R, typically a sub-item. Without
    this, 20 busy cells would starve every ingredient.
- The claim removal is computed from the selection and delayed to match the pass-through exactly,
  so downstream cells never see an item that is already claimed (fixes bug #4).
- Idle happens only when F is empty.

### 4.3 Chest requests sized by measured crafting speed

- Each cell measures its **craft time while working**: a counter adds 1 per tick while
  "Read working" is on, and the value is sampled and reset on the "Read recipe finished" pulse.
  Waiting for ingredients does not count. Modules and beacons are measured automatically.
- Crafts to buffer: `N = max(window / craft_ticks, N_min)`. Window ≈ 1200 ticks (20 s), N_min = 2.
  Before the first craft finishes, craft_ticks = 0, divide-by-zero gives 0, and N_min applies.
- Request per chest = `ingredient × N / 4` (4 chests share the load).
- Turn on **trash unrequested** in the cell chests, so leftovers from a finished recipe return to
  storage.

### 4.4 Assigning helpers by recipe ratio

> **History, not the decision.** Options A–C below are the alternatives explored on the way. What
> was decided is under "Decisions so far": Option C's *leave on starvation*, with a total budget
> instead of C's window, no inbound check or fill ratio, and the simple re-pick instead of C's
> "go to the ingredient". Option A's turn-taking was rejected. C's ingredient targeting may be tried
> later as an experiment, if it turns out simple (user: "if it is simple to implement then we could
> try it out").

Goal example (from the user): electronic circuits need about 2 EC assemblers per 1 copper cable
assembler. The real number depends on the modpack and on modules.

**Option A: ask the starving cells (recommended).**

- Add two shared buses, separate from the chain:
  - **Assigned A[X]**: every cell outputs 1 for its latched item, so A[X] = cells working on X.
  - **Starving S[X]**: a cell outputs 1 for its item while its assembler reports
    `item_ingredient_shortage`.
- Helper rule:
  - Never join an item whose cells are starving (S[X] > 0). More machines will not help; its
    ingredients are the bottleneck.
  - Among the rest, pick the max of `(D[X] + B[X]) / (A[X] + 1)`, i.e. the most work per machine.
- This converges on the real ratio by itself:
  - EC cells starve for cable, so helpers go to cable.
  - Once cable keeps up, EC cells stop starving, so helpers join EC.
  - Surplus cable fills its buffer and leaves F, which frees those cells.
- Because it measures actual behaviour, it adapts to beacons and modules with no recipe data.
- Anti-churn:
  - Only one helper re-evaluates per tick: a global clock, where cell k decides when
    `clock mod 20 = k`.
  - A helper switches only if the new score beats its current item by a margin, e.g. ×1.5.
  - Every helper assignment has a minimum hold time, about 10 s.

**Option B: compute the ratio.**

- Machines needed for X ∝ `rate needed × craft time / products per craft`.
- Craft time could be shared from the cells' measurements (a bus with Σ craft_ticks per item ÷ A[X]).
  But products per craft and ingredient amounts per sub-item are not available as signals, so it
  needs an authored per-recipe table of about 179 entries.
- That table goes wrong silently when recipes or modules change. Exact, but brittle.

**Option C: helpers leave when they starve (the user's idea, expanded). Supersedes A's
one-at-a-time turns.**

Every helper decides for itself and at the same moment as the others, with no turn-taking.

1. **What counts as starving.** Count a tick as starved only when both of these hold:
   - The assembler is **not working**: "Read working" is off while a recipe is set.
   - At least one of its ingredients is **not inbound**: that ingredient is on F with D > 0, so the
     network has none to send. This tells "robots are slow" (stay) apart from "there is nothing to
     bring" (leave).
   - Early-warning variant: the chest **fill ratio**, i.e. min over ingredients of
     `contents × 100 / request`. Being below a threshold (e.g. 25%) counts as starving before the
     machine actually stops. The request is known, because the cell computes it in 4.3.
2. **Measuring it.** Count starved ticks inside a 10 s window, reset by a shared clock. **Leave at
   300 starved ticks.** That covers both examples with one rule:
   - Starved continuously: it leaves after 5 s.
   - Starved 50% of the time: it leaves after 10 s.
   - Working normally: it never leaves.

   A fixed window misses starvation that straddles a reset. A second counter offset by 5 s, with
   "leave if either reaches 300", halves that error. A leaky integrator cannot hit both examples:
   any decay makes the 50% case take longer than 10 s.
3. **Where a helper goes when it leaves: the ingredient that starved it.** It picks the ingredient
   with the largest D among its own ingredients that are short (green "Read ingredients" ∩ F).
   Helpers therefore walk down the recipe tree to the bottleneck. EC helpers starving for cable
   become cable helpers. The ratio emerges from the measurements and follows beacons and modules.
   If no ingredient is craftable (a raw plate is short), it falls back to the best other item on F.
4. **Overshoot corrects itself.** If too many helpers move to cable, cable fills its buffer (4.1) and
   leaves F. That frees them, and they rejoin by score.
5. **Owners never leave because they starve.** They keep their item alive until its batch is done.
   Only helpers move.
6. **Optional damping without turns.** Give cell k a leave threshold of `300 + 10·k` ticks, so a
   group of starving helpers peels off a few at a time instead of all on the same tick.
7. **Cost:** about 6–7 combinators per cell. Starved condition: 2. Window counter: 2. Leave
   decision: 1. Ingredient target selector: 1–2. Plus one shared clock.

**Can the circuit network tell whether an ingredient is "inbound"? Checked online and in-engine.**

- **No direct signal.** No circuit option reads items carried by robots or headed for a chest. The
  API offers only `read_items_mode` = logistics | missing_requests | none on roboports and
  `read_contents`/`set_requests` on chests (local docs). Forum: "not possible to read the items that
  are about to be delivered" (https://forums.factorio.com/viewtopic.php?p=672736).
- **Indirect signal: missing requests already nets out reservations.** Missing = requested − what
  the network can supply. The 0.2.7 reproduction saw the rig's 200 request show up as 146–200,
  i.e. 200 minus what was already reserved or in flight. A known quirk: whether reserved items are
  subtracted depends on the type of chest they come from (2.0.32 report,
  https://forums.factorio.com/viewtopic.php?p=662599). So **"ingredient X is on the missing list
  (D > 0)" = "the network cannot send X" = not inbound.** This is the usable check, and it is a
  network-wide test, not a per-chest one.
- **Chest fill ratio: a chest can do both, but this creates feedback (measured in 2.1.24).** A
  requester in `set_requests` mode accepted `read_contents = true`. It writes its contents onto the
  same wire that sets its requests, so request = set + contents, and the requests ran away (200 →
  462 within 380 ticks). The ratio needs the contents read some other way:
  - an inserter reading its hand,
  - or a separate plain chest,
  - or subtracting the contents back out with a combinator that sees only the chest (each × −1 on
    the opposite wire colour, so the two cancel).
  The test copy was reverted.

### 4.5 Cost and constraints

- About 3 extra combinators at the head and about 6 per cell for 4.1–4.3. The decided helper logic
  adds about 5 per cell: starvation budget counter 1, leave decision 1, leave counter 1, modulo 1,
  selector 1. No shared clock.
- The test rig must get its own logistic network, or be wired like the head. **Any circuit-set
  requester chest on network 18 feeds the list.**

### 4.6 Status and next steps

- **Nothing is built yet.** A build was started and stopped by the user before it produced
  anything. There is no modified save and no blueprint.
- Plan for the next session:
  1. Set up the copy (§0).
  2. Switch off the rig chest's requests in the copy.
  3. Rebuild the logic in place on the existing mall: keep the assemblers, chests and inserters, and
     re-wire the combinators by script, so the result fits the user's layout.
  4. Head + C1–C3 first, verify with short tests, then all 20 cells.
  5. Export a blueprint string to `.claude/tmp/recursive-mall-redesign/blueprint.txt`.
- What to verify, by observable effects:
  - every cell works while anything is requested, and all are idle when nothing is;
  - no recipe flicker;
  - helpers converge on the bottleneck;
  - ingredient shortages get cells;
  - batches end at stock ≥ B.
- Tunable constants that are still guesses:
  - buffer B = 1 stack;
  - craft-time window 1200 ticks, N_min 2;
  - starvation budget 300 ticks.
- Not yet decided in detail (the builder's call, recorded here when made):
  - The exact signals for "is helper" and "leave count" inside the latch.
  - Whether a preempted helper (4.2) also resets its budget. Proposed: yes, like any new item.
  - How the owner/helper flag survives the 2-tick chain alignment.

## 5. Sources

- FFF-394 (set recipe, dump inventory): https://factorio.com/blog/post/fff-394
- FFF-428 (roboport missing requests): https://factorio.com/blog/post/fff-428
- Missing-requests net semantics (fixed in 2.0.48): https://forums.factorio.com/128584
- Read ingredients + set recipe on the same wire: https://forums.factorio.com/viewtopic.php?p=686256
- Recursive mall, fluctuating assignments: https://forums.factorio.com/viewtopic.php?p=643393
- Snapshot latch with a delayed reset: https://forums.factorio.com/viewtopic.php?p=675412
- Selector order stability: https://forums.factorio.com/viewtopic.php?p=643270
- Copper cable: https://wiki.factorio.com/Copper_cable

## 6. Scratch evidence

The per-tick logs (`rep_*` for 0.2.5, `r7_*`/`m7_*` for 0.2.7) were in the first session's
scratchpad, which is session-specific and gets cleared. Treat them as gone: the findings in §1–§3
are the record. Re-measure in a fresh copy if a number needs checking.
