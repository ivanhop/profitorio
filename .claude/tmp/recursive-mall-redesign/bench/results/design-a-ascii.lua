-- Design A build: hysteresis list, F/R lists, owner/helper/preempt, starvation-budget helpers,
-- chest requests from measured craft time. Load harness.lua first, then pipe this file in.
-- Then: /silent-command rcon.print(A.build(20))   (or A.build(3) for C1-C3 only)
-- RULE: the probe client flattens each block to one line, so no trailing "--" comments on code lines.
/silent-command
A = {}
A.s = game.surfaces.nauvis
A.BIG = 1048576
A.BIG2 = 2097152
A.BUDGET = 600
A.WINDOW = 300
A.LOFF = 720720
A.BDIV = 10
local W = defines.wire_connector_id
A.IR, A.IG, A.OR, A.OG, A.R, A.G = W.combinator_input_red, W.combinator_input_green, W.combinator_output_red, W.combinator_output_green, W.circuit_red, W.circuit_green
function A.v(n) return {type = "virtual", name = n} end
A.EACH, A.EVERY, A.ANY = A.v("signal-each"), A.v("signal-everything"), A.v("signal-anything")
A.RED, A.GRN, A.BOTH = {red = true, green = false}, {red = false, green = true}, {red = true, green = true}
function A.cond(sig, net, cmp, k, ct) return {first_signal = sig, first_signal_networks = net, comparator = cmp, constant = k, compare_type = ct or "and"} end
function A.out(sig, net) return {signal = sig, copy_count_from_input = true, networks = net} end
function A.kout(sig, k) return {signal = sig, copy_count_from_input = false, constant = k} end
A.ents = {}
function A.place(name, pos, dir)
  local e = A.s.create_entity{name = name, position = pos, direction = dir or 0, force = "player", raise_built = false}
  assert(e, "cannot place " .. name .. " at " .. serpent.line(pos))
  A.ents[#A.ents + 1] = e
  return e
end
function A.dist(a, b) local dx, dy = a.position.x - b.position.x, a.position.y - b.position.y return math.sqrt(dx * dx + dy * dy) end
A.bad = {}
function A.wire(a, ca, b, cb)
  local reach = math.min(a.prototype.get_max_circuit_wire_distance(), b.prototype.get_max_circuit_wire_distance())
  if A.dist(a, b) > reach then A.bad[#A.bad + 1] = string.format("%s@%.1f,%.1f-%s@%.1f,%.1f %.2f", a.name, a.position.x, a.position.y, b.name, b.position.x, b.position.y, A.dist(a, b)) end
  a.get_wire_connector(ca, true).connect_to(b.get_wire_connector(cb, true), false)
end
function A.dec(e, conds, outs, elses) e.get_control_behavior().parameters = {conditions = conds, outputs = outs, else_outputs = elses or {}} end
function A.ari(e, p) e.get_control_behavior().parameters = p end
function A.sel(e, p) e.get_control_behavior().parameters = p end
function A.const(e, sigs)
  local cb = e.get_control_behavior()
  local sec = cb.get_section(1) or cb.add_section()
  for i, v in ipairs(sigs) do sec.set_slot(i, {value = {type = v[3] or "item", name = v[1], quality = "normal"}, min = v[2]}) end
end
function A.at(pos, name) return A.s.find_entities_filtered{position = pos, radius = 0.6, name = name}[1] end
---
/silent-command
function A.clear()
  for _, area in pairs({{{-246, 100}, {-213, 138}}, {{-213, 102}, {-204, 142}}, {{-259, 102}, {-248, 142}}}) do
    for _, e in pairs(A.s.find_entities_filtered{area = area, type = {"arithmetic-combinator", "decider-combinator", "selector-combinator", "constant-combinator"}}) do e.destroy() end
  end
  for _, e in pairs(A.s.find_entities_filtered{area = {{-252, 99}, {-208, 138.9}}}) do
    if e.valid and e.get_wire_connectors then
      for id, c in pairs(e.get_wire_connectors(false)) do
        if c.wire_type == defines.wire_type.red or c.wire_type == defines.wire_type.green then c.disconnect_all() end
      end
    end
  end
end
function A.head()
  local h = {}
  h.RC = A.at({-219, 105}, "roboport")
  h.RM = A.at({-226, 105}, "roboport")
  h.RC.get_control_behavior().read_items_mode = defines.control_behavior.roboport.read_items_mode.logistics
  h.RM.get_control_behavior().read_items_mode = defines.control_behavior.roboport.read_items_mode.missing_requests
  h.MK = A.place("constant-combinator", {-223.5, 106.5}, 0)
  h.SF = A.place("decider-combinator", {-221.5, 105}, 0)
  h.NEG = A.place("arithmetic-combinator", {-222, 106.5}, 12)
  h.AM = A.place("arithmetic-combinator", {-223.5, 105}, 0)
  h.AS = A.place("arithmetic-combinator", {-222.5, 105}, 0)
  h.HL = A.place("decider-combinator", {-223, 103.5}, 4)
  h.BS = A.place("selector-combinator", {-225, 102.5}, 4)
  h.FO = A.place("decider-combinator", {-221, 101.5}, 4)
  h.RH = A.place("arithmetic-combinator", {-219, 101.5}, 4)
  h.CF = A.place("selector-combinator", {-217, 101.5}, 4)
  h.BD = A.place("arithmetic-combinator", {-227, 102.5}, 4)
  A.dec(h.SF, {A.cond(A.EACH, A.BOTH, ">", 0, "or")}, {A.out(A.EACH, A.BOTH)})
  A.ari(h.NEG, {first_signal = A.EACH, second_constant = -1, operation = "*", output_signal = A.EACH})
  A.ari(h.AM, {first_signal = A.EACH, first_signal_networks = A.RED, second_signal = A.EACH, second_signal_networks = A.GRN, operation = "*", output_signal = A.EACH})
  A.ari(h.AS, {first_signal = A.EACH, first_signal_networks = A.RED, second_signal = A.EACH, second_signal_networks = A.GRN, operation = "*", output_signal = A.EACH})
  A.sel(h.BS, {operation = "stack-size"})
  A.ari(h.BD, {first_signal = A.EACH, second_constant = A.BDIV, operation = "/", output_signal = A.EACH})
  A.dec(h.HL, {A.cond(A.EACH, A.GRN, ">", 0, "or"), A.cond(A.EACH, A.RED, "<", A.BIG / 2), A.cond(A.EACH, A.RED, ">", A.BIG, "or")}, {A.kout(A.EACH, A.BIG)})
  A.dec(h.FO, {A.cond(A.EACH, A.RED, ">", A.BIG, "or")}, {A.out(A.EACH, A.RED)})
  A.ari(h.RH, {first_signal = A.EACH, second_constant = 2, operation = "*", output_signal = A.EACH})
  A.sel(h.CF, {operation = "count", count_signal = A.v("signal-N")})
  A.wire(h.RC, A.R, h.SF, A.IR)
  A.wire(h.SF, A.OR, h.NEG, A.IR)
  A.wire(h.NEG, A.OG, h.AS, A.IG)
  A.wire(h.RM, A.G, h.AM, A.IG)
  A.wire(h.MK, A.R, h.AM, A.IR)
  A.wire(h.MK, A.R, h.AS, A.IR)
  A.wire(h.MK, A.R, h.BS, A.IR)
  A.wire(h.AM, A.OR, h.HL, A.IR)
  A.wire(h.AS, A.OR, h.HL, A.IR)
  A.wire(h.BS, A.OR, h.BD, A.IR)
  A.wire(h.BD, A.OR, h.HL, A.IR)
  A.wire(h.HL, A.OR, h.HL, A.IR)
  A.wire(h.AM, A.OG, h.HL, A.IG)
  A.wire(h.AS, A.OG, h.HL, A.IG)
  A.wire(h.HL, A.IR, h.FO, A.IR)
  A.wire(h.FO, A.OR, h.RH, A.IR)
  A.wire(h.FO, A.OR, h.CF, A.IR)
  A.wire(h.FO, A.OG, h.CF, A.OG)
  A.h = h
  return h
end
---
/silent-command
function A.mask()
  if A.MASK then return A.MASK end
  local old = A.at({-223.5, 106.5}, "constant-combinator")
  local m = {}
  for _, sec in pairs(old.get_control_behavior().sections) do for _, f in pairs(sec.filters) do if f.value and f.value.name then m[#m + 1] = f.value.name end end end
  A.MASK = m
  return m
end
function A.setmask(e)
  local sec = e.get_control_behavior().get_section(1) or e.get_control_behavior().add_section()
  for i, n in ipairs(A.MASK) do sec.set_slot(i, {value = {type = "item", name = n, quality = "normal"}, min = 1}) end
end
---
/silent-command
A.REL = {MULT = {2.5, 1.5, 4}, HOLD = {4.5, 0.5, 4}, DIVREN = {4.5, 2.5, 4}, DLY1 = {6.5, 0.5, 4}, COUNTER = {8.5, 0.5, 4}, DLY2 = {6, 2, 0}, PASS = {7, 2, 0}, SELR = {8, 2, 0}, TAKE = {9, 2, 0}}
A.KIND = {MULT = "arithmetic-combinator", HOLD = "decider-combinator", DIVREN = "arithmetic-combinator", DLY1 = "arithmetic-combinator", COUNTER = "decider-combinator", DLY2 = "arithmetic-combinator", PASS = "decider-combinator", SELR = "selector-combinator", TAKE = "decider-combinator", LATCH = "decider-combinator", SELF = "selector-combinator", BUDGET = "decider-combinator", LEAVES = "decider-combinator", MOD = "arithmetic-combinator", KC = "constant-combinator"}
function A.region(side)
  if side == "R" then return -213, -205, 103, 141 end
  return -258, -249, 103, 141
end
function A.candidates(name, side)
  local x0, x1, y0, y1 = A.region(side)
  local c = {}
  for ty = y0, y1 do for tx = x0, x1 do
    if name == "constant-combinator" then c[#c + 1] = {{tx + 0.5, ty + 0.5}, 0}
    else
      if ty + 1 <= y1 then c[#c + 1] = {{tx + 0.5, ty + 1}, 0} end
      if tx + 1 <= x1 then c[#c + 1] = {{tx + 1, ty + 0.5}, 4} end
    end
  end end
  return c
end
function A.pick(name, side, partners, cellc)
  local best, bestcost
  for _, cand in ipairs(A.candidates(name, side)) do
    local p = cand[1]
    local ok = true
    local cost = 0
    for _, q in ipairs(partners) do
      local dx, dy = p[1] - q.position.x, p[2] - q.position.y
      local d = math.sqrt(dx * dx + dy * dy)
      if d > 8.6 then ok = false break end
      cost = cost + d
    end
    if ok then
      if side == "R" then cost = p[2] * 10 + cost * 0.1 + math.abs(p[1] + 210) * 0.01 else cost = -p[2] * 10 + cost * 0.1 end
      if (not bestcost or cost < bestcost) and A.s.can_place_entity{name = name, position = p, direction = cand[2], force = "player"} then best, bestcost = cand, cost end
    end
  end
  assert(best, "no slot for " .. name .. " side " .. side .. " near " .. serpent.line(cellc))
  return A.place(name, best[1], best[2])
end
---
/silent-command
function A.cellparams(c, k)
  local BIG, BIG2 = A.BIG, A.BIG2
  local C, P, N, L, X = A.v("signal-C"), A.v("signal-P"), A.v("signal-N"), A.v("signal-L"), A.v("signal-X")
  A.dec(c.TAKE, {A.cond(A.EACH, A.GRN, ">=", BIG2, "or"), A.cond(A.EVERY, A.RED, "<", BIG2), A.cond(A.EACH, A.GRN, ">", 0, "or"), A.cond(A.EVERY, A.GRN, "<", BIG2), A.cond(A.EVERY, A.RED, "<", BIG)}, {A.out(A.EACH, A.GRN)})
  A.dec(c.LATCH, {A.cond(A.EACH, A.RED, ">=", BIG2, "or"), A.cond(A.EACH, A.GRN, ">", 0), A.cond(A.EACH, A.RED, ">=", BIG, "or"), A.cond(A.EACH, A.RED, "<", BIG2), A.cond(A.EACH, A.GRN, ">", 0), A.cond(A.EVERY, A.RED, "<", BIG2), A.cond(C, A.RED, ">", -A.BUDGET)}, {A.out(A.EACH, A.RED)})
  A.dec(c.BUDGET, {A.cond(A.ANY, A.RED, ">=", BIG, "or"), A.cond(A.EVERY, A.RED, "<", BIG2), A.cond(C, A.RED, ">", -A.BUDGET), A.cond(A.ANY, A.GRN, ">", 0)}, {A.out(C, A.BOTH), A.kout(C, -1)})
  A.dec(c.LEAVES, {A.cond(C, A.RED, "=", 2 - A.BUDGET, "or"), A.cond(C, A.GRN, "=", 0)}, {A.out(L, A.GRN), A.kout(L, -1)}, {A.out(L, A.GRN)})
  A.dec(c.PASS, {A.cond(A.EACH, A.RED, "=", 0, "or"), A.cond(A.EACH, A.GRN, ">", 0)}, {A.out(A.EACH, A.GRN)})
  A.sel(c.SELR, {operation = "select", select_max = true, index_constant = 0})
  A.sel(c.SELF, {operation = "select", select_max = true, index_signal = X})
  A.ari(c.MOD, {first_signal = L, first_signal_networks = A.RED, second_signal = N, second_signal_networks = A.GRN, operation = "%", output_signal = X})
  A.ari(c.DLY1, {first_signal = A.EACH, second_constant = 0, operation = "+", output_signal = A.EACH})
  A.ari(c.DLY2, {first_signal = A.EACH, second_constant = 0, operation = "+", output_signal = A.EACH})
  A.dec(c.COUNTER, {A.cond(P, A.GRN, "=", 0, "or"), A.cond(A.ANY, A.GRN, ">", 0)}, {A.out(C, A.BOTH)}, {A.kout(P, 1)})
  A.ari(c.DIVREN, {first_constant = A.WINDOW, second_signal = C, second_signal_networks = A.RED, operation = "/", output_signal = N})
  A.dec(c.HOLD, {A.cond(P, A.RED, "!=", 0, "or")}, {A.out(N, A.RED)}, {A.out(N, A.GRN)})
  A.ari(c.MULT, {first_signal = A.EACH, first_signal_networks = A.GRN, second_signal = N, second_signal_networks = A.RED, operation = "*", output_signal = A.EACH})
  A.const(c.KC, {{"signal-L", A.LOFF + k, "virtual"}})
  local cb = c.ASM.get_control_behavior()
  cb.circuit_set_recipe = true
  cb.circuit_read_ingredients = true
  cb.circuit_read_contents = false
  cb.circuit_read_working = true
  cb.circuit_working_signal = C
  cb.circuit_read_recipe_finished = true
  cb.circuit_recipe_finished_signal = P
  cb.input_networks = A.RED
  cb.output_networks = A.GRN
  for _, ch in pairs(c.CH) do
    local ccb = ch.get_control_behavior()
    ccb.set_requests = true
    ch.get_requester_point().trash_not_requested = true
  end
end
---
/silent-command
function A.cell(k)
  local asm = H.cells()[k]
  local left = k > 10
  local ax, y0 = asm.position.x, asm.position.y - 1.5
  local c = {k = k, ASM = asm}
  for name, r in pairs(A.REL) do
    local x = left and (ax - r[1]) or (ax + r[1])
    local d = r[3]
    if left and d == 4 then d = 12 end
    c[name] = A.place(A.KIND[name], {x, y0 + r[2]}, d)
  end
  c.CH = A.s.find_entities_filtered{area = {{ax - 4, y0 + 0.1}, {ax + 4, y0 + 2.9}}, name = "requester-chest"}
  assert(#c.CH == 4, "cell " .. k .. " has " .. #c.CH .. " requester chests")
  local side = left and "L" or "R"
  c.LATCH = A.pick(A.KIND.LATCH, side, {c.TAKE}, asm.position)
  c.SELF = A.pick(A.KIND.SELF, side, {c.TAKE, c.LATCH}, asm.position)
  c.BUDGET = A.pick(A.KIND.BUDGET, side, {c.LATCH, c.COUNTER}, asm.position)
  c.LEAVES = A.pick(A.KIND.LEAVES, side, {c.BUDGET}, asm.position)
  c.MOD = A.pick(A.KIND.MOD, side, {c.LEAVES, c.SELF}, asm.position)
  c.KC = A.pick(A.KIND.KC, side, {c.MOD}, asm.position)
  A.cellparams(c, k)
  local w = A.wire
  w(c.TAKE, A.IR, c.TAKE, A.OR)
  w(c.TAKE, A.IR, c.PASS, A.IR)
  w(c.PASS, A.IR, asm, A.R)
  w(c.TAKE, A.IR, c.LATCH, A.IR)
  w(c.LATCH, A.IR, c.LATCH, A.OR)
  w(c.LATCH, A.IR, c.BUDGET, A.IR)
  w(c.BUDGET, A.IR, c.BUDGET, A.OR)
  w(c.BUDGET, A.IR, c.LEAVES, A.IR)
  w(c.SELR, A.OG, c.TAKE, A.IG)
  w(c.SELF, A.OG, c.TAKE, A.IG)
  w(c.DLY1, A.IG, c.SELR, A.IG)
  w(c.DLY1, A.OG, c.DLY2, A.IG)
  w(c.DLY2, A.OG, c.PASS, A.IG)
  w(asm, A.G, c.MULT, A.IG)
  w(c.MULT, A.IG, c.COUNTER, A.IG)
  w(c.COUNTER, A.IG, c.BUDGET, A.IG)
  w(c.BUDGET, A.IG, c.LEAVES, A.IG)
  w(c.LEAVES, A.OG, c.LEAVES, A.IG)
  table.sort(c.CH, function(a, b) local da, db = A.dist(a, c.MULT), A.dist(b, c.MULT) return da < db end)
  for i, ch in ipairs(c.CH) do
    if i <= 2 then w(i == 1 and c.MULT or c.CH[i - 1], i == 1 and A.IG or A.G, ch, A.G) end
    w(i == 1 and c.MULT or c.CH[i - 1], i == 1 and A.OR or A.R, ch, A.R)
  end
  w(c.COUNTER, A.OR, c.COUNTER, A.IR)
  w(c.COUNTER, A.IR, c.DIVREN, A.IR)
  w(c.DIVREN, A.IR, c.DIVREN, A.OR)
  w(c.DIVREN, A.IR, c.HOLD, A.IR)
  w(c.HOLD, A.OG, c.HOLD, A.IG)
  w(c.HOLD, A.OR, c.MULT, A.IR)
  w(c.LEAVES, A.OR, c.MOD, A.IR)
  w(c.KC, A.R, c.MOD, A.IR)
  w(c.MOD, A.OR, c.SELF, A.IR)
  w(c.LATCH, A.IG, c.SELF, A.IG)
  w(c.SELF, A.IG, c.MOD, A.IG)
  return c
end
---
/silent-command
function A.near(list, e)
  local best, bd
  for _, x in ipairs(list) do local d = A.dist(x[1], e) if not bd or d < bd then best, bd = x, d end end
  return best
end
function A.fbus(c) return {{c.LATCH, A.IG}, {c.SELF, A.IG}, {c.MOD, A.IG}} end
function A.build(n)
  A.MASK = nil
  A.mask()
  A.clear()
  A.bad = {}
  A.ents = {}
  local h = A.head()
  A.setmask(h.MK)
  A.C = {}
  local prevpass = {h.RH, A.OG}
  local prevf = {{h.CF, A.OG}}
  local poles = {{-220.5, 135.5}, {-225.5, 137.5}, {-231.5, 137.5}, {-238.5, 135.5}}
  local fpoles = {{-221.5, 103.5}, {-228.5, 101.5}, {-231.5, 101.5}, {-236.5, 101.5}, {-244.5, 102.5}, {-249.5, 107.5}}
  local order = {}
  for k = 1, n do order[#order + 1] = k end
  for _, k in ipairs(order) do
    local c = A.cell(k)
    A.C[k] = c
    if k == 11 then
      local pp = {}
      for i, p in ipairs(poles) do pp[i] = A.at(p, "medium-electric-pole") end
      A.wire(prevpass[1], prevpass[2], pp[1], A.R)
      for i = 2, #pp do A.wire(pp[i - 1], A.R, pp[i], A.R) end
      prevpass = {pp[#pp], A.R}
    end
    A.wire(prevpass[1], prevpass[2], c.DLY1, A.IG)
    prevpass = {c.PASS, A.OG}
    local fb = A.fbus(c)
    if k == 11 then prevf = {} end
    if #prevf > 0 then
      local best, bd, mine
      for _, a in ipairs(prevf) do for _, b in ipairs(fb) do local d = A.dist(a[1], b[1]) if not bd or d < bd then best, bd, mine = a, d, b end end end
      A.wire(best[1], best[2], mine[1], mine[2])
    end
    prevf = fb
    A.C[k].fb = fb
  end
  if n >= 11 then
    local fp = {}
    for i, p in ipairs(fpoles) do fp[i] = A.at(p, "medium-electric-pole") end
    A.wire(h.FO, A.OG, fp[1], A.G)
    for i = 2, #fp do A.wire(fp[i - 1], A.G, fp[i], A.G) end
    local top = A.C[n].fb
    local best, bd
    for _, b in ipairs(top) do local d = A.dist(fp[#fp], b[1]) if not bd or d < bd then best, bd = b, d end end
    A.wire(fp[#fp], A.G, best[1], best[2])
  end
  return "built " .. n .. " cells, " .. #A.ents .. " combinators; reach violations: " .. #A.bad .. " " .. table.concat(A.bad, "; ")
end
---
/silent-command
function A.export()
  local keep = {}
  for _, e in pairs(A.s.find_entities_filtered{area = {{-245, 102}, {-214, 138}}}) do if e.unit_number then keep[e.unit_number] = true end end
  for _, e in pairs(A.ents) do if e.valid then keep[e.unit_number] = true end end
  for _, p in pairs({{-221.5, 103.5}, {-228.5, 101.5}, {-231.5, 101.5}, {-236.5, 101.5}, {-244.5, 102.5}, {-249.5, 107.5}}) do keep[A.at(p, "medium-electric-pole").unit_number] = true end
  local inv = game.create_inventory(1)
  inv.insert("blueprint")
  local bp = inv[1]
  local map = bp.create_blueprint{surface = A.s, force = "player", area = {{-260, 100}, {-204, 143}}}
  local old = bp.get_blueprint_entities()
  local renum, out = {}, {}
  for _, be in ipairs(old) do
    local src = map[be.entity_number]
    if src and src.valid and src.unit_number and keep[src.unit_number] then renum[be.entity_number] = #out + 1 out[#out + 1] = be end
  end
  local nw = 0
  for i, be in ipairs(out) do
    local ws = {}
    for _, w in ipairs(be.wires or {}) do if renum[w[1]] and renum[w[3]] then ws[#ws + 1] = {renum[w[1]], w[2], renum[w[3]], w[4]} nw = nw + 1 end end
    be.entity_number = i
    be.wires = (#ws > 0) and ws or nil
  end
  bp.set_blueprint_entities(out)
  bp.label = "recursive mall design A"
  local str = bp.export_stack()
  local n = #out
  inv.destroy()
  A.bpcount = n .. " entities, " .. nw .. " wire ends"
  return str
end
