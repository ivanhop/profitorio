-- Benchmark recorder: records facts for bench/analyze.py. Load after harness.lua, mask.lua, H.rig_off() and the design.
-- Then: /silent-command rcon.print(BN.start("r6", "beacon", 50, 54000))  ... poll rcon.print(BN.status()) until done.
-- Writes script-output/bench_<tag>.json. Owns on_nth_tick(1) while running: never run H.run at the same time.
-- RULES (client flattens each block to one line): whole-line comments only, never trailing ones.
/silent-command
BN = {}
BN.STATUS = {}
for k, v in pairs(defines.entity_status) do BN.STATUS[v] = k end
BN.AM2 = prototypes.entity["assembling-machine-2"]
function BN.on_mask()
  assert(H.MASK, "load mask.lua first")
  local m = {}
  for _, names in pairs(H.MASK) do for _, n in pairs(names) do m[n] = true end end
  return m
end
function BN.recipe_ok(r, force)
  local craftable = false
  for _, cat in pairs(r.categories) do if BN.AM2.crafting_categories[cat] then craftable = true end end
  if not craftable then return false end
  if not force.recipes[r.name] or not force.recipes[r.name].enabled then return false end
  for _, i in pairs(r.ingredients) do if i.type ~= "item" then return false end end
  for _, p in pairs(r.products) do if p.type ~= "item" then return false end end
  return true
end
function BN.pick(item, force)
  local own = prototypes.recipe[item]
  if own and BN.recipe_ok(own, force) then return own end
  local rs = prototypes.get_recipe_filtered{{filter = "has-product-item", elem_filters = {{filter = "name", name = item}}}}
  for _, r in pairs(rs) do if BN.recipe_ok(r, force) then return r end end
end
function BN.rec(r)
  local o = {energy = r.energy, ingredients = {}, products = {}}
  for _, i in pairs(r.ingredients) do o.ingredients[#o.ingredients + 1] = {i.name, i.amount} end
  for _, p in pairs(r.products) do o.products[#o.products + 1] = {p.name, p.amount or ((p.amount_min + p.amount_max) / 2)} end
  return o
end
function BN.tree(target)
  local mask, force, tree, recipes = BN.on_mask(), game.forces.player, {}, {}
  local function walk(item)
    if tree[item] or not mask[item] then return end
    local r = BN.pick(item, force)
    if not r then return end
    tree[item] = r.name
    recipes[r.name] = BN.rec(r)
    for _, i in pairs(r.ingredients) do walk(i.name) end
  end
  walk(target)
  return tree, recipes
end
function BN.cell_chests(cell)
  local p, out = cell.position, {}
  for _, ins in pairs(H.s.find_entities_filtered{type = "inserter", area = {{p.x - 3, p.y - 3}, {p.x + 3, p.y + 3}}}) do
    if ins.drop_target == cell and ins.pickup_target then out[#out + 1] = ins.pickup_target end
  end
  return out
end
function BN.held(st)
  local o = {}
  for i, e in pairs(st.cells) do
    local n = e.get_inventory(defines.inventory.crafter_input).get_item_count()
    for _, ch in pairs(st.chests[i]) do n = n + ch.get_item_count() end
    o[i] = n
  end
  return o
end
function BN.joules(st)
  local o = {}
  for proto, v in pairs(st.stats.input_counts) do
    o[proto] = v
    if not st.types[proto] then st.types[proto] = prototypes.entity[proto] and prototypes.entity[proto].type or proto end
  end
  return o
end
function BN.trigger_count(target) return H.at(H.TRIGGER, "requester-chest").get_item_count(target) end
---
/silent-command
function BN.start(tag, target, n, cap)
  target, n, cap = target or "beacon", n or 50, cap or 54000
  local cells = H.cells()
  local pole = H.s.find_entities_filtered{area = H.MALL_AREA, type = "electric-pole", limit = 1}[1]
  local note = ""
  local fr = game.forces.player.recipes[target]
  if fr and not fr.enabled then fr.enabled = true note = " (unlocked " .. target .. " on this copy: the save has not researched it)" end
  -- The sandbox keeps the save's 11 ghosts, all beacons: robots would build them from the batch (61 made, 50 delivered).
  local ghosts = H.s.find_entities_filtered{type = {"entity-ghost", "tile-ghost"}}
  for _, g in pairs(ghosts) do g.destroy() end
  note = note .. ", removed " .. #ghosts .. " ghosts"
  local tree, recipes = BN.tree(target)
  assert(tree[target], "no AM2 recipe on the mask for " .. target)
  local net = H.net()
  local st = {tag = tag, target = target, n = n, cap = cap, t0 = game.tick, cells = cells, chests = {}, c = {},
    stats = pole.electric_network_statistics, types = {}, events = {}, samples = {}, made = 0,
    trig0 = BN.trigger_count(target), t_made_n = nil, t_delivered_n = nil, done = false}
  local out = {tag = tag, target = target, n = n, cap = cap, cells = {}, recipes = recipes, tree = tree, stock0 = {}}
  for item in pairs(tree) do out.stock0[item] = net.get_item_count(item) end
  for i, e in pairs(cells) do
    st.chests[i] = BN.cell_chests(e)
    local r = e.get_recipe()
    st.c[i] = {r = r and r.name or "-", s = BN.STATUS[e.status] or "?", pf = e.products_finished, dump = {}}
    if r and not recipes[r.name] then recipes[r.name] = BN.rec(r) end
    out.cells[i] = {x = e.position.x, y = e.position.y, speed = e.crafting_speed, prod = e.productivity_bonus}
    st.events[#st.events + 1] = {0, i, "r", st.c[i].r}
    st.events[#st.events + 1] = {0, i, "s", st.c[i].s}
  end
  st.out = out
  st.samples[1] = {t = 0, j = BN.joules(st), held = BN.held(st)}
  BN.st = st
  H.demand(target, st.trig0 + n)
  script.on_nth_tick(1, BN.tick)
  game.tick_paused = false
  return "bench " .. tag .. ": " .. n .. " " .. target .. ", cap " .. cap .. ", tree " .. serpent.line(tree) .. note
end
function BN.tick()
  local st = BN.st
  local now = game.tick - st.t0
  local idle = true
  for i, e in pairs(st.cells) do
    local c = st.c[i]
    local pf = e.products_finished
    if pf > c.pf then
      local cr = c.r ~= "-" and c.r or c.lr
      st.events[#st.events + 1] = {now, i, "c", cr, pf - c.pf}
      if cr == st.target then st.made = st.made + pf - c.pf end
      c.pf = pf
    end
    local r = e.get_recipe()
    r = r and r.name or "-"
    if r ~= c.r then
      st.events[#st.events + 1] = {now, i, "r", r}
      if c.r ~= "-" then c.lr = c.r end
      c.r = r
      if r ~= "-" and not st.out.recipes[r] then st.out.recipes[r] = BN.rec(prototypes.recipe[r]) end
    end
    if r ~= "-" then idle = false end
    local s = BN.STATUS[e.status] or "?"
    if s ~= c.s then st.events[#st.events + 1] = {now, i, "s", s} c.s = s end
    local dump = {}
    for _, it in pairs(e.get_inventory(defines.inventory.assembling_machine_dump).get_contents()) do
      dump[it.name] = (dump[it.name] or 0) + it.count
      local grew = dump[it.name] - (c.dump[it.name] or 0)
      if grew > 0 then st.events[#st.events + 1] = {now, i, "d", it.name, grew} end
    end
    c.dump = dump
  end
  if not st.t_made_n and st.made >= st.n then st.t_made_n = now end
  if not st.t_delivered_n and BN.trigger_count(st.target) - st.trig0 >= st.n then st.t_delivered_n = now end
  local finished = (st.t_delivered_n and idle) or now >= st.cap
  if now % 60 == 0 or finished then
    st.samples[#st.samples + 1] = {t = now, j = BN.joules(st), held = BN.held(st),
      delivered = BN.trigger_count(st.target) - st.trig0, stock = H.net().get_item_count(st.target)}
  end
  if finished then
    script.on_nth_tick(1, nil)
    game.tick_paused = true
    st.done = true
    st.ended = now >= st.cap and not (st.t_delivered_n and idle) and "cap" or "idle"
    BN.save(now)
  end
end
function BN.save(now)
  local st, o = BN.st, BN.st.out
  o.t_end, o.ended, o.t_made_n, o.t_delivered_n = now, st.ended, st.t_made_n, st.t_delivered_n
  o.events, o.samples, o.types = st.events, st.samples, st.types
  helpers.write_file("bench_" .. st.tag .. ".json", helpers.table_to_json(o), false, 0)
end
function BN.status()
  local st = BN.st
  if not st then return "not started" end
  local now = game.tick - st.t0
  if st.done then
    local tr = H.at(H.TRIGGER, "requester-chest")
    local req = tr.get_requester_point().get_section(1).get_slot(1)
    return "done " .. st.tag .. " at " .. now .. " (" .. st.ended .. "), made " .. st.made .. ", delivered at " .. tostring(st.t_delivered_n)
      .. ", in trigger " .. (BN.trigger_count(st.target) - st.trig0) .. ", network stock " .. H.net().get_item_count(st.target)
      .. ", trigger request " .. serpent.line(req and req.value and {req.value.name, req.min}) .. ", wrote bench_" .. st.tag .. ".json"
  end
  return "running " .. now .. "/" .. st.cap .. ", made " .. st.made .. ", delivered " .. (BN.trigger_count(st.target) - st.trig0)
end
rcon.print("bench loaded")
