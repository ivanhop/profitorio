-- Round 6, adaptive buffer grown once per stockout event, on top of r2-b. Load after harness.lua, mask.lua, H.rig_off() and r2-b/build.lua.
-- Per item B (memory, starts at 0) grows by stack/4 on the rising edge of a re-arm latch L. L sets when stock <= 0 AND raw D > 0 (X1), and holds until stock > B/2.
-- 7 combinators at the head: X1 (stockout), Q (B/2 - stock), L (re-arm latch), X2 (L delayed, negated), M (edge x step), MEM (B), H2 (B/2). All real entities and wires.
-- RULES (client flattens each block to one line): whole-line comments only, never trailing ones.
/silent-command
local W, EACH, RED, GREEN = MB.W, MB.EACH, MB.RED, MB.GREEN
local cond, outc, outcopy, dec, ari, net = MB.cond, MB.outc, MB.outcopy, MB.dec, MB.ari, MB.net
local hd = MB.head
local cx, cy = -222, 102.5
local function spot(name)
  for dy = 0, 6 do
    for _, y in pairs({cy + dy, cy - dy}) do
      for dx = 0, 12 do
        for _, x in pairs({cx - dx, cx + dx}) do
          if MB.s.can_place_entity{name = name, position = {x, y}, direction = 4, force = "player"} then
            local e = MB.make(name, {x, y}, 4)
            cx, cy = x, y
            return e
          end
        end
      end
    end
  end
  error("no spot for " .. name)
end
local AD = {}
MB.ad = AD
local K = 1000000
AD.x1 = dec(spot("decider-combinator"), {cond(EACH, GREEN, ">", 0), cond(EACH, RED, "=", 0)}, {outc(EACH, K)})
AD.q = ari(spot("arithmetic-combinator"), {first_signal = EACH, first_signal_networks = GREEN, second_signal = EACH, second_signal_networks = RED, operation = "-", output_signal = EACH})
-- L green = K*X1 + B/2 - stock. Set: green > K/2 (only X1 reaches it). Hold: own red > 0 AND green >= 0, i.e. stock <= B/2. With B = 0 that still needs stock >= 1 to re-arm.
AD.l = dec(spot("decider-combinator"), {cond(EACH, GREEN, ">", K / 2), cond(EACH, RED, ">", 0, nil, "or"), cond(EACH, GREEN, ">=", 0)}, {outc(EACH, 1)})
AD.x2 = ari(spot("arithmetic-combinator"), {first_signal = EACH, first_signal_networks = RED, second_constant = -1, operation = "*", output_signal = EACH})
AD.m = dec(spot("decider-combinator"), {cond(EACH, GREEN, ">", 0)}, {outcopy(EACH, RED)})
AD.mem = ari(spot("arithmetic-combinator"), {first_signal = EACH, first_signal_networks = RED, second_constant = 0, operation = "+", output_signal = EACH})
AD.h2 = ari(spot("arithmetic-combinator"), {first_signal = EACH, first_signal_networks = GREEN, second_constant = 2, operation = "/", output_signal = EACH})
local function cut(e, id) e.get_wire_connector(id, true).disconnect_all() end
cut(hd.bsc, W.combinator_output_green)
cut(hd.hl, W.combinator_input_green)
local n = 0
n = n + net({{hd.bsc, W.combinator_output_red}, {AD.m, W.combinator_input_red}}, "step")
n = n + net({{hd.mm, W.combinator_output_green}, {hd.ms, W.combinator_output_green}, {AD.x1, W.combinator_input_green}}, "rawD")
-- hd.neg outputs -stock only for stock > 0 (hd.pos filters), so an item absent on X1's red input has stock <= 0.
n = n + net({{hd.neg, W.combinator_output_red}, {AD.x1, W.combinator_input_red}}, "negstock")
-- Q reads stock (pos net, stock > 0 only) on red and B/2 on green, and sums with X1 onto L's green.
n = n + net({{hd.pos, W.combinator_output_red}, {AD.q, W.combinator_input_red}}, "stock")
n = n + net({{AD.q, W.combinator_output_green}, {AD.x1, W.combinator_output_green}, {AD.l, W.combinator_input_green}}, "setq")
n = n + net({{AD.l, W.combinator_output_red}, {AD.l, W.combinator_input_red}, {AD.x2, W.combinator_input_red}}, "Lself")
n = n + net({{AD.l, W.combinator_output_green}, {AD.x2, W.combinator_output_green}, {AD.m, W.combinator_input_green}}, "edge")
n = n + net({{AD.m, W.combinator_output_red}, {AD.mem, W.combinator_input_red}, {AD.mem, W.combinator_output_red}}, "Bmem")
n = n + net({{AD.mem, W.combinator_output_green}, {AD.h2, W.combinator_input_green}}, "B")
n = n + net({{AD.h2, W.combinator_output_green}, {hd.hl, W.combinator_input_green}, {AD.q, W.combinator_input_green}}, "halfB")
n = n + net({{AD.h2, W.combinator_output_red}, {hd.hl, W.combinator_input_red}}, "halfB-on-D")
local pos = {}
for k, e in pairs(AD) do pos[#pos + 1] = k .. serpent.line(e.position) end
rcon.print("re-armed adaptive buffer built, 7 combinators, " .. n .. " wires: " .. table.concat(pos, " "))
---
/silent-command
-- Read B (the memory output, green side carries only MEM) and the latch L for chosen items. Usage: rcon.print(MB.ad_B({"copper-cable"}))
function MB.ad_B(items)
  local o = {}
  for _, it in pairs(items) do
    local s = {type = "item", name = it}
    o[#o + 1] = it .. "=" .. MB.ad.mem.get_signal(s, defines.wire_connector_id.combinator_output_green) .. (MB.ad.l.get_signal(s, defines.wire_connector_id.combinator_output_red) > 0 and "L" or "")
  end
  return table.concat(o, " ")
end
rcon.print("ad_B ready")
---
/silent-command
-- Log B every 600 ticks while the game runs. MB.ad_log holds the lines; MB.ad_dump() returns them.
MB.ad_log = {}
MB.ad_items = {"copper-cable", "advanced-circuit", "kr-electronic-components", "kr-research-server", "electronic-circuit"}
script.on_nth_tick(600, function() MB.ad_log[#MB.ad_log + 1] = game.tick .. " " .. MB.ad_B(MB.ad_items) end)
function MB.ad_dump() return table.concat(MB.ad_log, "
") end
rcon.print("B logger on")
