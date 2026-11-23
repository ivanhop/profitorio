-- Design B: helpers walk down the recipe tree. Builds the whole design on a fresh colin0.2.7 copy.
-- Load harness.lua first and call H.rig_off(). Then pipe this file through probe_client.py.
-- Optional before loading: /silent-command MB = {NCELLS = 3, BUDGET = 120, K = 2, SP = 3, NCH = 4, BLIND = false}
-- BLIND = true is the comparison variant: exhausted helpers re-pick the least-staffed F item instead of walking down.
-- RULES (client flattens each block to one line): whole-line comments only, never trailing ones.
/silent-command
MB = MB or {}
MB.NCELLS = MB.NCELLS or 20
MB.BUDGET = MB.BUDGET or 120
MB.K = MB.K or 2
MB.SP = MB.SP or 3
MB.BDIV = MB.BDIV or 4
MB.NCH = MB.NCH or 4
if MB.HELP == nil then MB.HELP = not MB.BLIND end
MB.s = game.surfaces.nauvis
MB.W = defines.wire_connector_id
function MB.v(n) return {type = "virtual", name = n} end
MB.EACH = MB.v("signal-each")
MB.RED = {red = true, green = false}
MB.GREEN = {red = false, green = true}
function MB.at(pos, name) return MB.s.find_entities_filtered{position = pos, radius = 0.6, name = name}[1] end
function MB.make(name, pos, dir)
  local e = MB.s.create_entity{name = name, position = pos, direction = dir or 0, force = "player", raise_built = false}
  assert(e, "cannot place " .. name .. " at " .. serpent.line(pos))
  return e
end
function MB.dec(e, conds, outs) e.get_control_behavior().parameters = {conditions = conds, outputs = outs} return e end
function MB.ari(e, p) e.get_control_behavior().parameters = p return e end
function MB.cond(sig, nets, cmp, rhs, rhsnets, andor)
  local c = {first_signal = sig, first_signal_networks = nets, comparator = cmp, compare_type = andor or "and"}
  if type(rhs) == "table" then c.second_signal = rhs c.second_signal_networks = rhsnets else c.constant = rhs end
  return c
end
function MB.outc(sig, k) return {signal = sig, copy_count_from_input = false, constant = k} end
function MB.outcopy(sig, nets) return {signal = sig, copy_count_from_input = true, networks = nets} end
function MB.pt(n) return {n[1], n[2]} end
-- Prim's tree over wire connectors so no hop exceeds wire reach. nodes = {{entity, connector_id}, ...}
function MB.net(nodes, tag)
  local n = #nodes
  if n < 2 then return 0 end
  local con, inT, best, from = {}, {}, {}, {}
  for i, nd in pairs(nodes) do con[i] = nd[1].get_wire_connector(nd[2], true) best[i] = math.huge end
  local function d(i, j) local a, b = nodes[i][1].position, nodes[j][1].position return (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 end
  inT[1] = true
  for j = 2, n do best[j] = d(1, j) from[j] = 1 end
  local made = 0
  for _ = 2, n do
    local bj, bv = nil, math.huge
    for j = 2, n do if not inT[j] and best[j] < bv then bj, bv = j, best[j] end end
    local i = from[bj]
    if con[i].owner == con[bj].owner and con[i].wire_connector_id == con[bj].wire_connector_id then
    else
      assert(con[i].can_wire_reach(con[bj]), (tag or "net") .. ": no reach " .. nodes[i][1].name .. serpent.line(nodes[i][1].position) .. " -> " .. nodes[bj][1].name .. serpent.line(nodes[bj][1].position))
      con[i].connect_to(con[bj], false)
      made = made + 1
    end
    inT[bj] = true
    for j = 2, n do if not inT[j] then local dv = d(bj, j) if dv < best[j] then best[j] = dv from[j] = bj end end end
  end
  return made
end
rcon.print("MB lib loaded")
---
/silent-command
-- 1. Record each cell's combinator slots, then clear the old logic: cell and head combinators, pole circuit wires.
local W = MB.W
MB.cells = H.cells()
MB.slots = {}
for k, a in pairs(MB.cells) do
  local x, y = a.position.x, a.position.y
  local x0, x1 = -222.1, -215.9
  if x < -230 then x0, x1 = -243.1, -236.9 end
  local sl = {free = {}}
  for _, e in pairs(MB.s.find_entities_filtered{area = {{x0 - 1, y - 1.6}, {x1 + 1, y + 1.6}}, type = {"arithmetic-combinator", "decider-combinator", "selector-combinator"}}) do
    local p = e.position
    if p.x >= x0 and p.x <= x1 and p.y > y - 1.6 and p.y < y + 1.6 then
      local rec = {pos = {p.x, p.y}, dir = e.direction}
      if e.type == "selector-combinator" and e.get_control_behavior().parameters.operation == "stack-size" then sl.req = rec else sl.free[#sl.free + 1] = rec end
      e.destroy()
    end
  end
  table.sort(sl.free, function(u, v) if u.pos[2] ~= v.pos[2] then return u.pos[2] < v.pos[2] end return u.pos[1] < v.pos[1] end)
  assert(sl.req and #sl.free == 8, "cell " .. k .. ": unexpected slots " .. #sl.free)
  MB.slots[k] = sl
end
MB.headslots = {}
for _, e in pairs(MB.s.find_entities_filtered{area = {{-224.6, 103}, {-220.4, 107.6}}, type = {"arithmetic-combinator", "decider-combinator", "selector-combinator"}}) do
  MB.headslots[#MB.headslots + 1] = {name = e.name, pos = {e.position.x, e.position.y}, dir = e.direction}
  e.destroy()
end
local stripped = 0
for _, p in pairs(MB.s.find_entities_filtered{area = {{-247, 100}, {-212, 139}}, type = {"electric-pole", "roboport"}}) do
  for _, id in pairs({W.circuit_red, W.circuit_green}) do local c = p.get_wire_connector(id, false) if c then stripped = stripped + c.connection_count c.disconnect_all() end end
end
rcon.print("cleared: cells " .. #MB.slots .. ", head combinators " .. #MB.headslots .. ", pole/roboport wires " .. stripped)
---
/silent-command
-- 2. Head: D = masked missing - masked stock; hysteresis latch; Q0 bus (red): F class 500000 + min(F,999) - 1000 per cell + HELP/100,
-- R bonus +1e6 for unstaffed F items, clock signal-Z (0..-100), idle candidate signal-dot. Y bus (green): 2e9 sole holder, 999999 shared.
local W, v, EACH, RED, GREEN = MB.W, MB.v, MB.EACH, MB.RED, MB.GREEN
local cond, outc, outcopy, dec, ari, make = MB.cond, MB.outc, MB.outcopy, MB.dec, MB.ari, MB.make
local hd = {}
MB.head = hd
hd.rbc = MB.at({-219, 105}, "roboport")
hd.rbm = MB.at({-226, 105}, "roboport")
hd.mask = MB.at({-223.5, 106.5}, "constant-combinator")
hd.pos = dec(make("decider-combinator", {-221.5, 105}, 0), {cond(EACH, RED, ">", 0)}, {outcopy(EACH)})
hd.neg = ari(make("arithmetic-combinator", {-222, 106.5}, 12), {first_signal = EACH, second_constant = -1, operation = "*", output_signal = EACH})
hd.mm = ari(make("arithmetic-combinator", {-223.5, 105}, 0), {first_signal = EACH, first_signal_networks = RED, second_signal = EACH, second_signal_networks = GREEN, operation = "*", output_signal = EACH})
hd.ms = ari(make("arithmetic-combinator", {-222.5, 105}, 0), {first_signal = EACH, first_signal_networks = RED, second_signal = EACH, second_signal_networks = GREEN, operation = "*", output_signal = EACH})
hd.dum = make("constant-combinator", {-223.5, 103.5}, 0)
hd.dum.get_control_behavior().get_section(1).set_slot(1, {value = {type = "virtual", name = "signal-dot", quality = "normal"}, min = 50000})
hd.bst = make("selector-combinator", {-227, 100.5}, 4)
hd.bst.get_control_behavior().parameters = {operation = "stack-size"}
hd.bsc = ari(make("arithmetic-combinator", {-227, 101.5}, 4), {first_signal = EACH, first_signal_networks = GREEN, second_constant = MB.BDIV, operation = "/", output_signal = EACH})
hd.hl = dec(make("decider-combinator", {-225, 100.5}, 4), {cond(EACH, RED, ">", 0)}, {outcopy(EACH, GREEN)})
hd.c1 = dec(make("decider-combinator", {-223, 100.5}, 4), {cond(EACH, RED, ">", 999)}, {outc(EACH, 500999)})
hd.c2 = dec(make("decider-combinator", {-221, 100.5}, 4), {cond(EACH, RED, ">", 0), cond(EACH, RED, "<=", 999)}, {outcopy(EACH, RED), outc(EACH, 500000)})
hd.clk = dec(make("decider-combinator", {-219, 100.5}, 4), {cond(v("signal-Z"), RED, ">", -100)}, {outcopy(v("signal-Z"), RED), outc(v("signal-Z"), -1)})
hd.an = ari(make("arithmetic-combinator", {-225, 101.5}, 4), {first_signal = EACH, first_signal_networks = GREEN, second_constant = -1000, operation = "*", output_signal = EACH})
hd.r = dec(make("decider-combinator", {-223, 101.5}, 4), {cond(EACH, RED, ">", 0), cond(EACH, GREEN, "=", 0)}, {outc(EACH, 1000000)})
hd.y1 = dec(make("decider-combinator", {-221, 101.5}, 4), {cond(EACH, RED, ">", 0), cond(EACH, GREEN, "=", -1000)}, {outc(EACH, 2000000000)})
hd.help = ari(make("arithmetic-combinator", {-217, 100.5}, 4), {first_signal = EACH, first_signal_networks = RED, second_constant = 100, operation = "/", output_signal = EACH})
hd.y2 = dec(make("decider-combinator", {-219, 101.5}, 4), {cond(EACH, RED, ">", 0), cond(EACH, GREEN, "<", -1000)}, {outc(EACH, 999999)})
local net = MB.net
net({{hd.rbc, W.circuit_red}, {hd.pos, W.combinator_input_red}}, "contents")
net({{hd.pos, W.combinator_output_red}, {hd.neg, W.combinator_input_red}}, "pos")
net({{hd.neg, W.combinator_output_green}, {hd.ms, W.combinator_input_green}}, "neg")
net({{hd.rbm, W.circuit_green}, {hd.mm, W.combinator_input_green}}, "missing")
net({{hd.mask, W.circuit_red}, {hd.mm, W.combinator_input_red}, {hd.ms, W.combinator_input_red}, {hd.bst, W.combinator_input_red}}, "mask")
net({{hd.bst, W.combinator_output_green}, {hd.bsc, W.combinator_input_green}}, "stack")
net({{hd.bsc, W.combinator_output_green}, {hd.hl, W.combinator_input_green}}, "buffer")
net({{hd.mm, W.combinator_output_red}, {hd.ms, W.combinator_output_red}, {hd.hl, W.combinator_input_red}, {hd.hl, W.combinator_output_red}, {hd.c1, W.combinator_input_red}, {hd.c2, W.combinator_input_red}, {hd.r, W.combinator_input_red}, {hd.y1, W.combinator_input_red}, {hd.y2, W.combinator_input_red}}, "D")
net({{hd.an, W.combinator_output_green}, {hd.r, W.combinator_input_green}, {hd.y1, W.combinator_input_green}, {hd.y2, W.combinator_input_green}}, "AN")
rcon.print("head built")
---
/silent-command
-- 3. Cells. Per cell: S selector, X decision, A1 incumbent threshold, L latch, K budget, T walk-down boost, Req chest requests.
local W, v, EACH, RED, GREEN = MB.W, MB.v, MB.EACH, MB.RED, MB.GREEN
local cond, outc, outcopy, dec, ari, make, net = MB.cond, MB.outc, MB.outcopy, MB.dec, MB.ari, MB.make, MB.net
MB.cell = {}
for k = 1, MB.NCELLS do
  local a, sl = MB.cells[k], MB.slots[k]
  local f = sl.free
  local c = {asm = a}
  c.s = make("selector-combinator", f[1].pos, f[1].dir)
  c.s.get_control_behavior().parameters = {operation = "select", select_max = true, index_constant = 0}
  c.x = dec(make("decider-combinator", f[2].pos, f[2].dir), {cond(EACH, GREEN, ">", v("signal-H"), GREEN), cond(v("signal-Z"), RED, "=", -MB.SP * k)}, {outc(EACH, 1), outc(v("signal-X"), -1)})
  c.a1 = ari(make("arithmetic-combinator", f[3].pos, f[3].dir), {first_signal = EACH, first_signal_networks = RED, second_signal = EACH, second_signal_networks = GREEN, operation = "*", output_signal = v("signal-H")})
  c.l = dec(make("decider-combinator", f[4].pos, f[4].dir), {cond(EACH, RED, ">", 0), cond(v("signal-X"), GREEN, "=", 0), cond(EACH, GREEN, ">", 0, nil, "or"), cond(v("signal-X"), GREEN, "<", 0)}, {outc(EACH, 1)})
  c.k = dec(make("decider-combinator", f[5].pos, f[5].dir), {cond(v("signal-X"), RED, "=", 0)}, {outcopy(v("signal-B"), GREEN), outc(v("signal-B"), -1)})
  local tconds = {cond(EACH, GREEN, ">", 0), cond(EACH, RED, ">", 300000), cond(v("signal-B"), GREEN, "<=", -MB.BUDGET)}
  if MB.BLIND then table.remove(tconds, 1) end
  c.t = dec(make("decider-combinator", f[6].pos, f[6].dir), tconds, {outc(EACH, 1000000)})
  c.req = ari(make("arithmetic-combinator", sl.req.pos, sl.req.dir), {first_signal = EACH, first_signal_networks = GREEN, second_constant = MB.K, operation = "*", output_signal = EACH})
  local cb = a.get_or_create_control_behavior()
  cb.circuit_set_recipe = true
  cb.circuit_read_ingredients = true
  cb.circuit_read_working = true
  cb.circuit_working_signal = v("signal-B")
  cb.circuit_read_recipe_finished = false
  cb.circuit_read_contents = false
  c.chests = MB.s.find_entities_filtered{position = a.position, radius = 3.6, name = "requester-chest"}
  assert(#c.chests == 4, "cell " .. k .. " has " .. #c.chests .. " requester chests")
  local chestnodes = {{c.req, W.combinator_output_red}}
  table.sort(c.chests, function(u, w) return u.position.x + 10 * u.position.y < w.position.x + 10 * w.position.y end)
  for i, ch in pairs(c.chests) do
    ch.get_requester_point().trash_not_requested = true
    local ccb = ch.get_or_create_control_behavior()
    ccb.set_requests = true
    ccb.read_contents = false
    if i <= MB.NCH then chestnodes[#chestnodes + 1] = {ch, W.circuit_red} end
  end
  net(chestnodes, "chests" .. k)
  net({{c.s, W.combinator_output_green}, {c.a1, W.combinator_output_green}, {c.x, W.combinator_input_green}}, "P" .. k)
  net({{c.x, W.combinator_output_green}, {c.l, W.combinator_input_green}}, "G" .. k)
  net({{c.x, W.combinator_output_red}, {c.k, W.combinator_input_red}}, "XF" .. k)
  net({{c.l, W.combinator_output_red}, {c.l, W.combinator_input_red}, {c.a1, W.combinator_input_red}, {a, W.circuit_red}}, "L" .. k)
  net({{a, W.circuit_green}, {c.k, W.combinator_input_green}, {c.k, W.combinator_output_green}, {c.t, W.combinator_input_green}, {c.req, W.combinator_input_green}}, "A" .. k)
  net({{c.t, W.combinator_output_green}, {c.s, W.combinator_input_green}}, "Tb" .. k)
  MB.cell[k] = c
end
rcon.print("cells built: " .. MB.NCELLS)
---
/silent-command
-- 4. Buses. Q0 (red) and Y (green) cross the bottom on the existing poles; O (green) and HELP (red) on three new poles.
local W, hd, net = MB.W, MB.head, MB.net
local p1 = {MB.at({-225.5, 137.5}, "medium-electric-pole"), MB.at({-231.5, 137.5}, "medium-electric-pole")}
MB.p2 = MB.p2 or {}
for i, x in pairs({-222.5, -229.5, -236.5}) do MB.p2[i] = MB.at({x, 138.5}, "medium-electric-pole") or MB.make("medium-electric-pole", {x, 138.5}) end
local q0 = {{hd.c1, W.combinator_output_red}, {hd.c2, W.combinator_output_red}, {hd.an, W.combinator_output_red}, {hd.r, W.combinator_output_red}, {hd.clk, W.combinator_input_red}, {hd.clk, W.combinator_output_red}, {hd.dum, W.circuit_red}, {hd.help, W.combinator_output_red}}
local help = {{hd.help, W.combinator_input_red}}
local y = {{hd.y1, W.combinator_output_green}, {hd.y2, W.combinator_output_green}}
local o = {{hd.an, W.combinator_input_green}}
for k = 1, MB.NCELLS do
  local c = MB.cell[k]
  q0[#q0 + 1] = {c.s, W.combinator_input_red}
  q0[#q0 + 1] = {c.x, W.combinator_input_red}
  q0[#q0 + 1] = {c.t, W.combinator_input_red}
  y[#y + 1] = {c.a1, W.combinator_input_green}
  o[#o + 1] = {c.l, W.combinator_output_green}
  if MB.HELP then help[#help + 1] = {c.t, W.combinator_output_red} end
end
if MB.NCELLS > 10 then
  for _, p in pairs(p1) do q0[#q0 + 1] = {p, W.circuit_red} y[#y + 1] = {p, W.circuit_green} end
  for _, p in pairs(MB.p2) do o[#o + 1] = {p, W.circuit_green} if MB.HELP then help[#help + 1] = {p, W.circuit_red} end end
end
rcon.print("buses: Q0 " .. net(q0, "Q0") .. " wires, Y " .. net(y, "Y") .. ", O " .. net(o, "O") .. ", HELP " .. net(help, "HELP"))
