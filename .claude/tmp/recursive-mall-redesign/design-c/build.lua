-- Design C: central bitmask dispatcher. Builds the whole design on a fresh colin0.2.7 copy.
-- Send with: python tools/check/probe_client.py --host 127.0.0.1 --port 2712N --password probe < build.lua
-- Blocks are flattened to one line each: whole-line comments only, never a trailing "--".
-- Knobs live in CFG (block 1). Re-running the whole file rebuilds from scratch (idempotent).
/silent-command
B = {s = game.surfaces.nauvis}
CFG = {
  K = 2,
  BUDGET = 900,
  P = 20,
  ASSIGN_EVERY = 5,
  REBAL_PHASE = 2,
  REBAL_RATIO = 2,
  T_REL = 1800,
  ALL = 1048575,
  LATCH = 268435456,
  LATCH_TEST = 134217728,
  STARVE = 1024,
}
local W = defines.wire_connector_id
B.C = {ri = W.combinator_input_red, gi = W.combinator_input_green, ro = W.combinator_output_red, go = W.combinator_output_green, r = W.circuit_red, g = W.circuit_green}
B.EACH = {type = "virtual", name = "signal-each"}
function B.v(n) return {type = "virtual", name = n} end
function B.NET(r, g) return {red = r, green = g} end
B.RED, B.GREEN = {red = true, green = false}, {red = false, green = true}
function B.at(pos, name) return B.s.find_entities_filtered{position = pos, radius = 0.6, name = name}[1] end
function B.place(name, x, y, dir)
  local e = B.s.create_entity{name = name, position = {x, y}, direction = dir or 0, force = "player"}
  assert(e, "could not place " .. name .. " at " .. x .. "," .. y)
  return e
end
function B.reach(e) return e.prototype.get_max_circuit_wire_distance() end
function B.dist(a, b) local dx, dy = a.position.x - b.position.x, a.position.y - b.position.y return math.sqrt(dx * dx + dy * dy) end
function B.wire(a, ac, b, bc)
  local d = B.dist(a, b)
  assert(d <= math.min(9.75, math.max(B.reach(a), B.reach(b))), "wire too long " .. d .. ": " .. a.name .. "@" .. a.position.x .. "," .. a.position.y .. " -> " .. b.name .. "@" .. b.position.x .. "," .. b.position.y)
  a.get_wire_connector(B.C[ac], true).connect_to(b.get_wire_connector(B.C[bc], true), false)
end
function B.net(list)
  local done = {list[1]}
  for i = 2, #list do
    local best, bd = nil, 1e9
    for _, m in pairs(done) do local d = B.dist(m[1], list[i][1]) if d < bd then best, bd = m, d end end
    B.wire(best[1], best[2], list[i][1], list[i][2])
    done[#done + 1] = list[i]
  end
end
function B.arith(x, y, dir, p) local e = B.place("arithmetic-combinator", x, y, dir) e.get_or_create_control_behavior().parameters = p return e end
function B.decider(x, y, dir, p) local e = B.place("decider-combinator", x, y, dir) e.get_or_create_control_behavior().parameters = p return e end
function B.selector(x, y, dir, p) local e = B.place("selector-combinator", x, y, dir) e.get_or_create_control_behavior().parameters = p return e end
function B.cond(sig, nets, cmp, rhs, rnets, ctype)
  local c = {first_signal = sig, first_signal_networks = nets, comparator = cmp, compare_type = ctype or "and"}
  if type(rhs) == "number" then c.constant = rhs else c.second_signal = rhs c.second_signal_networks = rnets end
  return c
end
function B.copy(sig, nets) return {signal = sig, copy_count_from_input = true, networks = nets} end
function B.const_out(sig, n) return {signal = sig, copy_count_from_input = false, constant = n} end
function B.cells()
  local c = {}
  for i = 0, 9 do c[#c + 1] = {side = "R", Y = 108.5 + 3 * i} end
  for i = 9, 0, -1 do c[#c + 1] = {side = "L", Y = 108.5 + 3 * i} end
  for k, cell in pairs(c) do
    local Y, R = cell.Y, cell.side == "R"
    cell.k = k - 1
    cell.asm = B.at({R and -224.5 or -234.5, Y}, "assembling-machine-2")
    local cx = R and -227.5 or -231.5
    cell.chests = {B.at({cx, Y - 1}, "requester-chest"), B.at({cx, Y}, "requester-chest"), B.at({cx, Y + 1}, "requester-chest"), B.at({R and -221.5 or -237.5, R and Y - 1 or Y + 1}, "requester-chest")}
    for _, ch in pairs(cell.chests) do assert(ch, "missing chest for cell " .. k) end
    cell.pos = R and {c5 = {-222, Y}, c1 = {-220, Y - 1}, c2 = {-218, Y - 1}} or {c5 = {-237, Y}, c1 = {-239, Y - 1}, c2 = {-241, Y - 1}}
    cell.dir = R and 4 or 12
  end
  return c
end
rcon.print("design C lib loaded")
---
/silent-command
local area = {{-249, 101}, {-211, 139}}
local in_area = function(p) return p.x >= area[1][1] and p.x <= area[2][1] and p.y >= area[1][2] and p.y <= area[2][2] end
local mask
for _, e in pairs(B.s.find_entities_filtered{area = area, name = "constant-combinator"}) do
  local cb = e.get_control_behavior()
  local n = 0
  for s = 1, cb.sections_count do n = n + #cb.get_section(s).filters end
  if n > 100 then mask = e end
end
assert(mask, "mask constant combinator not found")
CFG.mask = {}
local mcb = mask.get_control_behavior()
for s = 1, mcb.sections_count do
  local fl = {}
  for i, f in pairs(mcb.get_section(s).filters) do if f.value then fl[#fl + 1] = {value = f.value, min = f.min} end end
  CFG.mask[#CFG.mask + 1] = fl
end
local removed = 0
for _, e in pairs(B.s.find_entities_filtered{area = {{-245, 102}, {-214, 139}}, type = {"arithmetic-combinator", "decider-combinator", "selector-combinator", "constant-combinator"}}) do
  e.destroy() removed = removed + 1
end
local cut = 0
for _, e in pairs(B.s.find_entities_filtered{area = area, type = {"electric-pole", "roboport", "logistic-container", "assembling-machine"}}) do
  for _, id in pairs({defines.wire_connector_id.circuit_red, defines.wire_connector_id.circuit_green}) do
    local con = e.get_wire_connector(id, false)
    if con then
      for _, c in pairs(con.connections) do
        if in_area(c.target.owner.position) then con.disconnect_from(c.target) cut = cut + 1 end
      end
    end
  end
end
rcon.print("removed " .. removed .. " combinators, cut " .. cut .. " wires, mask sections " .. #CFG.mask)
---
/silent-command
local E = B.EACH
B.cellents = {}
for _, cell in pairs(B.cells()) do
  local k, p, d = cell.k, cell.pos, cell.dir
  local acb = cell.asm.get_or_create_control_behavior()
  acb.circuit_set_recipe = true
  acb.circuit_read_ingredients = true
  acb.circuit_read_working = true
  acb.circuit_working_signal = B.v("signal-W")
  acb.circuit_read_contents = false
  acb.circuit_read_recipe_finished = false
  acb.input_networks = B.RED
  acb.output_networks = B.GREEN
  for _, ch in pairs(cell.chests) do
    local ccb = ch.get_or_create_control_behavior()
    ccb.set_requests = true
    ccb.read_contents = false
    ch.get_requester_point().trash_not_requested = true
  end
  local c1 = B.arith(p.c1[1], p.c1[2], d, {first_signal = E, first_signal_networks = B.RED, second_constant = 2 ^ k, operation = "AND", output_signal = E})
  local c2 = B.decider(p.c2[1], p.c2[2], d, {conditions = {B.cond(E, B.RED, "!=", 0), B.cond(B.v("signal-W"), B.GREEN, "=", 0)}, outputs = {B.const_out(E, CFG.STARVE + 1)}, else_outputs = {B.const_out(E, 1)}})
  local c5 = B.arith(p.c5[1], p.c5[2], d, {first_signal = E, first_signal_networks = B.GREEN, second_constant = CFG.K, operation = "*", output_signal = E})
  B.net({{c1, "ro"}, {cell.asm, "r"}, {c2, "ri"}})
  B.net({{cell.asm, "g"}, {c2, "gi"}, {c5, "gi"}})
  local chnet = {{c5, "ro"}}
  for _, ch in pairs(cell.chests) do chnet[#chnet + 1] = {ch, "r"} end
  B.net(chnet)
  B.cellents[k + 1] = {c1 = c1, c2 = c2, c5 = c5}
end
for i = 1, 19 do
  if i ~= 10 then
    local a, b = B.cellents[i], B.cellents[i + 1]
    B.wire(a.c1, "ri", b.c1, "ri")
    B.wire(a.c2, "ro", b.c2, "ro")
  end
end
rcon.print("cells built")
---
/silent-command
local E, L = B.EACH, CFG
local h = {}
local mask = B.place("constant-combinator", -216.5, 137.5, 0)
local mcb = mask.get_or_create_control_behavior()
while mcb.sections_count > 0 do mcb.remove_section(1) end
for _, fl in pairs(CFG.mask) do local sec = mcb.add_section() for i, f in pairs(fl) do sec.set_slot(i, f) end end
h.mask = mask
local rc = B.at({-213, 137}, "roboport") local rm = B.at({-213, 133}, "roboport")
rc.get_or_create_control_behavior().read_items_mode = defines.control_behavior.roboport.read_items_mode.logistics
rm.get_or_create_control_behavior().read_items_mode = defines.control_behavior.roboport.read_items_mode.missing_requests
h.L1 = B.decider(-216, 136.5, 4, {conditions = {B.cond(E, B.RED, ">", 0)}, outputs = {B.copy(E, B.RED)}})
h.L2 = B.arith(-216, 135.5, 4, {first_signal = E, first_signal_networks = B.RED, second_constant = -1, operation = "*", output_signal = E})
h.L3 = B.selector(-218, 135.5, 4, {operation = "stack-size"})
h.Lat = B.decider(-218, 136.5, 4, {conditions = {
    B.cond(E, B.GREEN, ">", E, B.RED, "or"), B.cond(E, B.RED, ">", 0, nil, "and"),
    B.cond(E, B.GREEN, ">", 0, nil, "or"), B.cond(E, B.RED, ">", L.LATCH_TEST, nil, "and")},
  outputs = {B.const_out(E, L.LATCH)}})
h.Nout = B.decider(-220, 136.5, 4, {conditions = {B.cond(E, B.RED, ">", L.LATCH_TEST)}, outputs = {B.copy(E, B.GREEN)}})
B.wire(rc, "r", h.L1, "ri")
B.wire(h.L1, "ro", h.L2, "ri")
B.wire(mask, "g", h.L3, "gi")
B.net({{h.Lat, "gi"}, {h.L2, "go"}, {h.L3, "go"}, {rm, "g"}, {h.Nout, "gi"}})
B.net({{h.Lat, "ri"}, {h.Lat, "ro"}, {h.L3, "ro"}, {h.Nout, "ri"}})
B.H = h
rcon.print("head list built")
---
/silent-command
local E, L, h, v = B.EACH, CFG, B.H, B.v
local function ar(x, y, f, fn, op, s, sn, out) local p = {first_signal = f, first_signal_networks = fn, operation = op, output_signal = out or E} if type(s) == "number" then p.second_constant = s else p.second_signal = s p.second_signal_networks = sn end return B.arith(x, y, 4, p) end
h.Mem = ar(-243, 137.5, E, B.GREEN, "AND", E, B.RED)
h.Mneg = ar(-241, 137.5, E, B.RED, "*", -1)
h.LB = ar(-239, 137.5, E, B.RED, "AND", E, B.GREEN)
h.A1 = ar(-237, 137.5, E, B.RED, "*", 1, nil, v("signal-X"))
h.A1n = ar(-241, 132.5, E, B.RED, "*", -1, nil, v("signal-Y"))
h.XY = B.place("constant-combinator", -233.5, 137.5, 0)
local sec = h.XY.get_or_create_control_behavior().get_section(1) or h.XY.get_control_behavior().add_section()
sec.set_slot(1, {value = {type = "virtual", name = "signal-X", quality = "normal"}, min = 1})
sec.set_slot(2, {value = {type = "virtual", name = "signal-Y", quality = "normal"}, min = -1})
h.RelM = ar(-243, 136.5, E, B.RED, "*", E, B.GREEN)
h.Amul = ar(-241, 136.5, E, B.GREEN, "*", v("signal-B"), B.RED)
h.A4 = ar(-239, 136.5, v("signal-X"), B.GREEN, "AND", v("signal-Y"), B.GREEN, v("signal-B"))
local nc = {}
for ph = 0, L.P - 1, L.ASSIGN_EVERY do nc[#nc + 1] = B.cond(E, B.GREEN, ">", 0, nil, "or") nc[#nc + 1] = B.cond(v("signal-C"), B.RED, "=", ph) end
h.Norm = B.decider(-243, 135.5, 4, {conditions = nc, outputs = {B.const_out(E, 1)}})
h.G = B.decider(-241, 135.5, 4, {conditions = {B.cond(E, B.GREEN, ">", 0)}, outputs = {B.const_out(E, L.ALL)}})
h.Clock = B.decider(-243, 134.5, 4, {conditions = {B.cond(v("signal-C"), B.RED, "<", L.P - 1)}, outputs = {B.copy(v("signal-C"), B.RED), B.const_out(v("signal-C"), 1)}})
h.Sel = B.selector(-243, 133.5, 4, {operation = "select", select_max = true, index_constant = 0})
h.Elig = B.decider(-241, 133.5, 4, {conditions = {B.cond(E, B.RED, ">", 0), B.cond(E, B.GREEN, "<=", 0)}, outputs = {B.copy(E, B.RED)}})
h.Score = ar(-239, 133.5, E, B.GREEN, "/", E, B.RED)
h.CoolLoop = ar(-243, 132.5, E, B.RED, "-", 1)
h.ONE = B.decider(-235, 137.5, 4, {conditions = {B.cond(E, B.GREEN, ">", 0)}, outputs = {B.const_out(E, 1)}})
h.CoolSetR = B.decider(-243, 131.5, 4, {conditions = {B.cond(E, B.RED, "!=", 0)}, outputs = {B.const_out(E, L.T_REL)}})
h.Q = B.decider(-243, 130.5, 4, {conditions = {B.cond(E, B.RED, ">=", E, B.GREEN), B.cond(E, B.GREEN, ">=", 3 * L.BUDGET)}, outputs = {B.const_out(E, -1)}})
h.AccMem = B.decider(-241, 130.5, 4, {conditions = {B.cond(E, B.RED, "<", E, B.GREEN)}, outputs = {B.copy(E, B.RED)}})
h.BA = ar(-239, 130.5, E, B.RED, "*", L.BUDGET)
h.Sdec = ar(-243, 129.5, E, B.RED, ">>", 10)
h.Adec = ar(-241, 129.5, E, B.RED, "AND", L.STARVE - 1)
rcon.print("head core placed")
---
/silent-command
local h, ce = B.H, B.cellents
local P1, P2 = B.at({-231.5, 137.5}, "medium-electric-pole"), B.at({-225.5, 137.5}, "medium-electric-pole")
local U = B.at({-227, 138}, "substation")
B.net({{h.Mem, "ro"}, {h.Mneg, "ri"}, {h.LB, "ri"}, {h.A1, "ri"}, {h.A1n, "ri"}, {ce[11].c1, "ri"}, {P1, "r"}, {P2, "r"}, {ce[10].c1, "ri"}})
B.net({{h.Mem, "gi"}, {h.Mem, "go"}, {h.RelM, "go"}, {h.Amul, "go"}})
B.net({{h.A4, "gi"}, {h.A1, "go"}, {h.A1n, "go"}, {h.XY, "g"}})
B.wire(h.Mneg, "go", h.LB, "gi")
B.wire(h.LB, "ro", h.RelM, "ri")
B.wire(h.A4, "ro", h.Amul, "ri")
B.wire(h.Norm, "go", h.Amul, "gi")
B.wire(h.G, "ro", h.Mem, "ri")
B.wire(h.Clock, "ro", h.Clock, "ri")
B.wire(h.Clock, "ro", h.Norm, "ri")
B.wire(h.Sel, "go", h.Norm, "gi")
B.wire(h.Elig, "ro", h.Sel, "ri")
B.wire(h.Score, "ro", h.Elig, "ri")
B.wire(h.CoolLoop, "go", h.Elig, "gi")
B.net({{h.CoolLoop, "ri"}, {h.CoolLoop, "ro"}, {h.CoolSetR, "ro"}})
B.wire(h.Q, "ro", h.CoolSetR, "ri")
B.wire(h.Q, "go", h.RelM, "gi")
B.net({{h.Sdec, "ro"}, {h.AccMem, "ri"}, {h.AccMem, "ro"}, {h.Q, "ri"}})
B.net({{h.BA, "go"}, {h.AccMem, "gi"}, {h.Q, "gi"}})
B.net({{h.Adec, "ro"}, {h.BA, "ri"}, {h.Score, "ri"}})
B.net({{h.Nout, "go"}, {U, "g"}, {h.ONE, "gi"}, {h.G, "gi"}, {h.Score, "gi"}})
B.net({{U, "r"}, {ce[10].c2, "ro"}, {h.ONE, "ro"}, {ce[11].c2, "ro"}, {h.Adec, "ri"}, {h.Sdec, "ri"}})
rcon.print("design C built")
---
/silent-command
local E, L, h, v = B.EACH, CFG, B.H, B.v
h.VF = B.decider(-239, 127.5, 4, {conditions = {B.cond(E, B.GREEN, ">=", 3)}, outputs = {B.copy(E, B.RED), B.const_out(E, 1)}})
h.SelMin = B.selector(-241, 127.5, 4, {operation = "select", select_max = false, index_constant = 0})
h.ToH = B.arith(-243, 126.5, 4, {first_signal = E, first_signal_networks = B.RED, second_constant = -L.REBAL_RATIO, operation = "*", output_signal = v("signal-H")})
h.ToH2 = B.arith(-243, 127.5, 4, {first_signal = E, first_signal_networks = B.GREEN, second_constant = 1, operation = "*", output_signal = v("signal-H")})
h.Trig = B.decider(-243, 128.5, 4, {conditions = {B.cond(E, B.RED, ">", 0), B.cond(v("signal-H"), B.GREEN, ">", 0), B.cond(v("signal-B"), B.GREEN, ">", L.ALL), B.cond(v("signal-C"), B.GREEN, "=", L.REBAL_PHASE)}, outputs = {B.const_out(E, -1)}})
B.wire(h.Score, "ro", h.VF, "ri")
B.wire(h.Adec, "go", h.VF, "gi")
B.wire(h.VF, "ro", h.SelMin, "ri")
B.wire(h.SelMin, "ro", h.ToH, "ri")
B.wire(h.SelMin, "ro", h.Trig, "ri")
B.wire(h.Sel, "go", h.ToH2, "gi")
B.net({{h.Trig, "gi"}, {h.ToH, "go"}, {h.ToH2, "go"}, {h.A4, "go"}, {h.Clock, "go"}})
B.wire(h.Trig, "go", h.RelM, "gi")
B.wire(h.Trig, "ro", h.CoolSetR, "ri")
rcon.print("rebalancer built")

