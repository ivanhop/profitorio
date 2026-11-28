-- Round 4, adaptive buffer, on top of r2-b. Load after harness.lua, mask.lua, H.rig_off() and r2-b/build.lua.
-- Per item B (memory, starts at 0) grows by stack/4 on each rising edge of raw D > 0. Latch on at D + B/2 > 0, off at D + B <= 0.
-- 5 combinators added at the head: X1 (D>0), X2 (delayed negation), M (edge x step), MEM (B), H2 (B/2). All real entities and wires.
-- RULES (client flattens each block to one line): whole-line comments only, never trailing ones.
/silent-command
local W, EACH, RED, GREEN = MB.W, MB.EACH, MB.RED, MB.GREEN
local cond, outc, outcopy, dec, ari, net = MB.cond, MB.outc, MB.outcopy, MB.dec, MB.ari, MB.net
local hd = MB.head
local function spot(name)
  for dy = 0, 6 do
    for _, y in pairs({102.5 + dy, 102.5 - dy}) do
      for dx = 0, 12 do
        for _, x in pairs({-222 - dx, -222 + dx}) do
          if MB.s.can_place_entity{name = name, position = {x, y}, direction = 4, force = "player"} then
            local e = MB.make(name, {x, y}, 4)
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
AD.x1 = dec(spot("decider-combinator"), {cond(EACH, GREEN, ">", 0)}, {outc(EACH, 1)})
AD.x2 = ari(spot("arithmetic-combinator"), {first_signal = EACH, first_signal_networks = GREEN, second_constant = -1, operation = "*", output_signal = EACH})
AD.m = dec(spot("decider-combinator"), {cond(EACH, RED, ">", 0)}, {outcopy(EACH, GREEN)})
AD.mem = ari(spot("arithmetic-combinator"), {first_signal = EACH, first_signal_networks = RED, second_constant = 0, operation = "+", output_signal = EACH})
AD.h2 = ari(spot("arithmetic-combinator"), {first_signal = EACH, first_signal_networks = GREEN, second_constant = 2, operation = "/", output_signal = EACH})
-- The latch's green input was the fixed stack/4 buffer; it now gets B/2. Step (stack/4) goes to M instead.
local function cut(e, id) e.get_wire_connector(id, true).disconnect_all() end
cut(hd.bsc, W.combinator_output_green)
cut(hd.hl, W.combinator_input_green)
-- hl now copies B/2 (its green), so with H2's constant B/2 on the D net: on at D + B/2 > 0, off at D + B <= 0.
local n = 0
n = n + net({{hd.bsc, W.combinator_output_green}, {AD.m, W.combinator_input_green}}, "step")
n = n + net({{hd.mm, W.combinator_output_green}, {hd.ms, W.combinator_output_green}, {AD.x1, W.combinator_input_green}}, "rawD")
n = n + net({{AD.x1, W.combinator_output_green}, {AD.x2, W.combinator_input_green}}, "delay")
n = n + net({{AD.x1, W.combinator_output_red}, {AD.x2, W.combinator_output_red}, {AD.m, W.combinator_input_red}}, "edge")
n = n + net({{AD.m, W.combinator_output_red}, {AD.mem, W.combinator_input_red}, {AD.mem, W.combinator_output_red}}, "Bmem")
n = n + net({{AD.mem, W.combinator_output_green}, {AD.h2, W.combinator_input_green}}, "B")
n = n + net({{AD.h2, W.combinator_output_green}, {hd.hl, W.combinator_input_green}}, "halfB")
n = n + net({{AD.h2, W.combinator_output_red}, {hd.hl, W.combinator_input_red}}, "halfB-on-D")
local pos = {}
for k, e in pairs(AD) do pos[#pos + 1] = k .. serpent.line(e.position) end
rcon.print("adaptive buffer built, 5 combinators, " .. n .. " wires: " .. table.concat(pos, " "))
---
/silent-command
-- Read B (the memory output, green side carries only MEM) for chosen items. Usage: rcon.print(MB.ad_B({"copper-cable"}))
function MB.ad_B(items)
  local o = {}
  for _, it in pairs(items) do o[#o + 1] = it .. "=" .. MB.ad.mem.get_signal({type = "item", name = it}, defines.wire_connector_id.combinator_output_green) end
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
