# Critique of r7 (IDEA.md)

Sources: `bench/results/bench_design-c.json` and `bench_r3-grace.json` analysed with `analyze.py`, plus `design-c/build.lua`, its notes, `r3-grace/notes.md`, `PROGRESS.md` and the 2.1 API. "Before delivery" means ticks 0 to t(50).

## Premises

| Premise | Verdict | Evidence |
|---|---|---|
| Ticks per item 857/114/57/14.3, ideal split 9.1/4.6/3.4/2.9 | **holds** | 15·60/1.05 = 857; 4·60/1.05/2 = 114; /4 = 57; 0.5·60/1.05/2 = 14.3. Cell-ticks 42.9k / 114.3k / 57.1k / 35.7k, divided by 12 500 |
| AC cells before delivery: C 3.8, grace 6.7 | **holds** | Computed 3.78 and 6.66 |
| "239 of 396 never crafted" (R4, C3, C4) | **fails** | 199 of C's 396 changes are to `-`. In C every transition is recipe → `-` → recipe (199 one way, 197 the other, none direct). Of the 197 recipe sets, **157 reached a craft (80%) and 39 were abandoned**. Grace abandoned **97 of 208 (47%)**. Grace abandons more often than C |
| C's no-recipe time is abandoned switches plus the 1800-t cooldown | **fails** | 39 abandonments × 561 t mean = 21.9k cell-ticks, 2.7% of C's 798k cell-ticks before delivery. 79% of C's no-recipe cell-ticks (317k of 400k) fall in the 17 108 ticks when 15 or more cells were free at once. One stall ran from 30 738 to 45 616, **14 878 t with 19 cells free**. In it, cell 20 kept `beacon` (so beacon stayed latched) and made 19 beacons, and there was **no release event**, so no cooldown could have been re-armed. An 1800-t cooldown cannot cover 14 878 t. Each stall starts with a whole item leaving the list (cable ×18 at 30 713–30 738, components ×18 at 21 383–21 602, AC ×7 at 12 624). r7 keeps that "unchanged" |
| C splits by count, so AC is under-weighted | **doubtful** | Among assigned cells, C already gave AC 38% (3.78 of 9.98) against an ideal 46%. Scaled to 20 cells that is AC 7.6, components 5.1, beacon 3.5, cable 3.4. Grace: AC 37%. C's AC deficit comes from unassigned cells, not from the score |

## Claims

| # | Verdict | Evidence |
|---|---|---|
| C1 AC ≥ 7.5 | **doubtful** (the number could hold, the mechanism is misattributed) | See the premise above: filling the free cells alone gives about 7.6. With T, IDEA's own fixed point (R1) is AC 11, components 2, cable 1.4. That is an overshoot that starves components |
| C2 components ≥ 3.5, cable 2–4, beacon ≤ 5 | **untestable as stated** | It rests entirely on urgency, and IDEA's own no-urgency estimate fails all three. Urgency fires on stock ≤ 0, but `get_item_count` is net of robot reservations and can go negative (PROGRESS l.191). In a pull system an intermediate sits at ≤ 0 whenever requests outrun stock, so U may saturate for every item and stop discriminating. U is capped at 4096 (fixed point of U = 2048 + U/2), a factor of ≤ 5, not the ×8 IDEA assumes. With 2 combinators the factor is either ⌊U/τ⌋+1 (5 integer steps; no effect below 1024; each step doubles the score, which is exactly the rebalancer's 2× trigger, so it will oscillate) or N·T16·(τ+U) (overflows int32 once N·T16 > 2^31/5120 = 419k, i.e. 460 components) |
| C3 no recipe < 15% | **doubtful** | The stalls are not cooldown-bound (see above), so "cooldown as a rank" and grace do not address 79% of the free time. It holds only if the unexplained stall cause happens to be fixed. Run 0 can test that (credit to it) |
| C4 ≤ 250 changes, ≥ 60% reaching a craft | **fails** | The ratio is computed over all changes (157/396 = 40%). r7 keeps C's memory, so every set is paired with a `-`, and the ratio is capped near 50% even if every set crafts. Per set, C is already at 80%. Reaching ≤ 250 would mean fewer unlatch drops, and r7 does not touch the list |
| C5 switching ≤ 12% | **doubtful** | Grace holds starving, never-crafted cells for 2048–4096 t, and the analyser counts all of it as switching (`segments`, l.90). C's abandoned switches lasted a median 497 t. r3-grace's own verdict was that a 900-idle-tick grace "hurt" and should be 300–450 (r3-grace/notes l.43–49; PROGRESS l.170). r7's expiry is 2.3–4.5× longer |
| C6 t(50) ≤ 20 000 | **untestable as stated** | It is C1–C4 stacked, with no measured component. "Useful" is not a mechanism: the analyser counts only the ideal crafts, so useful% ≈ perfect/t_end (C: 23% × 54 000 × 20 = 248k ≈ 250k; grace: 12 577/25 591 = 49%). "Useful ≥ 55%" just restates t_end ≤ 22 700. With t(50) = 20 000 that means idle within 2700 t, which contradicts C7's own 4000 |
| C7 idle ≤ t(50) + 4000 | **fails** (likely) | "Unchanged list" means C's B = 1 stack (design-c/notes l.26), against grace's stack/4. After delivery, C made **17 beacons, 260 AC, 138 components and 698 cable**, and was still busy at the cap, 14 083 t later. Refilling 17 beacons alone is 17/50 × 12 500 = 4250 t at *perfect* efficiency, and about 6900 t at the 62% that C6 claims |
| C8 ≤ 110 MJ per beacon, ≤ 1.7× robot items | **doubtful** (wrong mechanism) | Dumps before delivery: C 3675 against grace 3568. Churn is the same. C used 6322 MJ to t(50) against grace's 5484 (more ticks), plus **1894 MJ (23%) after delivery** on the buffer refill. The analyser's MJ per beacon divides by every beacon made, so surplus beacons improve it. C's robot items are 31 640 / 15 300 = 2.07×, mostly from post-delivery crafts. C4 cannot fix that |

## Mechanisms

| Claim | Verdict | Evidence |
|---|---|---|
| Wk adds A − S, decoded by Adec/Sdec | **fails as stated** | Adec = V AND 1023 = **A + 1**: ONE puts 1 per latched item on the V net (build.lua l.235; notes l.32). T is then biased by (A+1−S)/(A−S): ×2 for a 1-cell item, ×1.3 for beacon at 3.4 cells. A latched item with no cells accrues phantom work against Pk = 0: T16 = 16·(2048+240)/4 ≈ 9150 after one epoch, so an unstaffed cable is weighted like beacon. That is an unmeasured second urgency. It needs one more combinator to subtract ONE |
| CF drops dumps because "they are not the recipe's item" | **doubtful** | It filters on C1's *commanded* recipe. Cable is an AC ingredient, and C reassigned AC → `-` → cable in 8 ticks (cell 1, 45 728 → 45 736), while a dump takes about 500 t. The dumped cable then counts as cable product and lowers T(cable) |
| R3: a stale G bit "only protects" | **doubtful** | A craft that finishes after a release (PROGRESS l.180: "current craft finishes ≤ 30") can pulse K after the bit is reassigned (5-tick cadence). That clears the *new* assignment's grace, the unsafe direction. CG is not gated on recipe |
| Pulse-mode hand read, one type per swing | **untestable from docs** | `hand_read_mode.pulse` exists (defines.md l.107–110). The docs don't say when it pulses. Plausible, unmeasured |
| int32 (Wk·16 ≈ 1.3e6, Work ≈ 2.2e7, the +2^26 rank) | **holds** with the ⌊U/τ⌋ form | 2.2e7 + 6.7e7 < 2^31. Wk steady state 2·2048·21·16 ≈ 1.4e6 |
| 163 combinators | **holds** arithmetically | The rows sum to 31; 100 + 32 + 31 = 163. Fitting 63 head combinators into slots that shrink by 2 per cell (C's head used freed cell slots C10–C14), within 9.75-tile wires, is untested |
| Grace expiry 2048–4096 t | **holds** arithmetically | |
| User constraints | **mostly hold** | T is measured, so there is no recipe table. CF maps a recipe to its own item, not to its ingredients. Fast inserters stay. **But** r7 inherits C's fixed B = 1 stack and silently drops the adaptive buffer the user adopted (PROGRESS l.76–92). Wire lengths are unverified |

## Test plan

- **Stages are not single-mechanism.** Run 1 bundles grace with cooldown-as-rank, so C3 cannot be split between them. Run 2 multiplies the score by T16 (×200 to ×13 700). That also removes any integer truncation of N/(A+1) (N/(A+1) < 1 rounds to 0, which C's Elig treats as ineligible). It is one candidate for the stall, so run 2 confounds "T" with "resolution".
- **Noise.** r6 delivered 45, then 30, on two copies, and r2-b's working share varied 79–86%. Two or three copies cannot resolve a 5% difference in means. "Every r7 copy beats the best r3-grace copy" is the sound criterion: keep it and drop the 5%-of-means test.
- Run 0 logs latched items only at the cap. The stall needs per-60-t logs of the latched list, Score, cooldown and free bit B.

## The three objections most likely to sink r7

1. **It fixes a problem C does not have.** C's switches already reach a craft 80% of the time, and its dumps equal grace's. Its loss is mass stalls: 79% of the free time, up to 14 878 t, with a latched item and no cooldown active. Nothing in r7 is shown to address them. *Settle it:* run 0 with per-60-t logging of the latched list, Score, Elig, cooldown and B through one stall. That shows why free cells get nothing.
2. **The unchanged list kills C7, C6 and C8.** C's 1-stack buffer kept the mall busy 14 000+ t after delivery and spent 23% of its energy there. *Settle it:* design-c with the cap raised to about 100 000 t, recording t_idle − t(50) and the MJ spent after t(50).
3. **The split rests on a truncated N, a biased T and an untested urgency.** By IDEA's own estimate, AC ends up at 11 and components at 2. The A+1 bias and phantom work distort T, and urgency is quantized to 2× steps that hit the rebalancer threshold. *Settle it:* run 2 and run 3 logging N, T16, U and A per item every 60 t. Compare the settled A with 9.1/4.6/3.4/2.9, and T16 with 912/1829/13 714/229.
