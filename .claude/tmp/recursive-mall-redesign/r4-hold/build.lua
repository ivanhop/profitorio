-- Round 4, hold after release. Applies on top of r2-b/build.lua (same server, MB.cell populated).
-- Optional before loading: /silent-command MB.HOLD = 450
-- Per cell, 2 combinators in the two free slots f[7], f[8]:
--   HC counter: while A1's incumbent threshold H = 0 (the latched item left the list), T counts up; H > 0 resets it.
--   HG gate: while 0 < T < HOLD, adds signal-H = 1e8 on the P net, so no candidate beats H and X cannot re-pick.
-- Idle cells (latched signal-dot) have H = 0 forever, so T is far past HOLD and they pick freely.
-- 1e8 stays above every Q0 + boost value (about 2.5e6) and below int overflow when added to a 2e9 incumbent H.
/silent-command
MB.HOLD = MB.HOLD or 450
local W, v, RED, GREEN = MB.W, MB.v, MB.RED, MB.GREEN
local cond, outc, outcopy, dec, make, net = MB.cond, MB.outc, MB.outcopy, MB.dec, MB.make, MB.net
local n = 0
for k = 1, MB.NCELLS do
  local c, f = MB.cell[k], MB.slots[k].free
  c.hc = dec(make("decider-combinator", f[7].pos, f[7].dir), {cond(v("signal-H"), RED, "=", 0)}, {outcopy(v("signal-T"), RED), outc(v("signal-T"), 1)})
  c.hg = dec(make("decider-combinator", f[8].pos, f[8].dir), {cond(v("signal-T"), RED, ">", 0), cond(v("signal-T"), RED, "<", MB.HOLD)}, {outc(v("signal-H"), 100000000)})
  n = n + net({{c.a1, W.combinator_output_red}, {c.hc, W.combinator_input_red}, {c.hc, W.combinator_output_red}, {c.hg, W.combinator_input_red}}, "HR" .. k)
  n = n + net({{c.x, W.combinator_input_green}, {c.hg, W.combinator_output_green}}, "HP" .. k)
end
rcon.print("hold built: HOLD " .. MB.HOLD .. ", " .. (2 * MB.NCELLS) .. " combinators, " .. n .. " wires")
